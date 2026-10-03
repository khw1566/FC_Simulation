"""새 수집 자료로 칸몬 건물만 재생성하고 기존 도로를 보존한다."""
import hashlib
import json
import shutil
from collections import Counter
from pathlib import Path
import numpy as np
from PIL import Image
from shapely.geometry import Polygon
from shapely import STRtree, union_all, constrained_delaunay_triangles
from kanmon_building_geometry import KanmonBuildingGeometry
from vector_stream_cache import VectorStreamCache
from osm_multipolygon_buildings import OsmMultipolygonBuildings
from building_source_store import BuildingSourceStore


class KanmonBuildingBuilder:
    ROOT = Path(__file__).resolve().parents[2]

    @staticmethod
    def read(path):
        return BuildingSourceStore.read(path)

    def build(self):
        folder = self.ROOT / "godot_project/assets/maps/kanmon_straits"
        meta = self.read(folder / "map_meta.json")
        geometry = KanmonBuildingGeometry(meta)
        old = self.read(self.ROOT / "godot_project" / meta["assets"]["buildings_roads"].removeprefix("res://"))
        raw = self.read(self.ROOT / "data/raw/buildings/kanmon_straits_buildings_20261003.json")
        nodes = {e["id"]: [e["lon"], e["lat"]] for e in raw["elements"] if e["type"] == "node"}
        osm_polygons, osm_specs = [], []
        rejected = Counter()
        for elem in raw["elements"]:
            tags = elem.get("tags", {})
            if elem["type"] != "way" or tags.get("building") in (None, "no"):
                continue
            ids = elem.get("nodes", [])
            if len(ids) < 4 or ids[0] != ids[-1] or any(i not in nodes for i in ids):
                rejected["osm_invalid_or_missing_nodes"] += 1
                continue
            for polygon in geometry.polygons([[nodes[i] for i in ids]]):
                osm_polygons.append(polygon)
                osm_specs.append({"id": "osm_" + str(elem["id"]), "source": "OpenStreetMap", "tags": tags})
        osm_tree = STRtree(osm_polygons)
        print(f"OSM 유효 외곽선 {len(osm_polygons)}", flush=True)
        gsi = self.read(self.ROOT / "data/raw/buildings/kanmon_gsi_buildings_20261003.json")
        unique = {}
        for feature in gsi["buildings"]:
            for polygon in geometry.polygons(feature["rings"]):
                unique.setdefault(geometry.key(polygon), polygon)
        gsi_polygons = list(unique.values())
        del unique, gsi, raw, nodes
        print(f"GSI 정확 중복 제거 후 {len(gsi_polygons)}", flush=True)
        tree = STRtree(gsi_polygons)
        parent = list(range(len(gsi_polygons)))

        def root(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        for i, polygon in enumerate(gsi_polygons):
            for j in tree.query(polygon):
                if j <= i:
                    continue
                overlap = polygon.intersection(gsi_polygons[j]).area
                if overlap > 1 and overlap / min(polygon.area, gsi_polygons[j].area) > .2:
                    parent[root(int(j))] = root(i)
        groups = {}
        for i, polygon in enumerate(gsi_polygons):
            groups.setdefault(root(i), []).append(polygon)
        polygons = list(osm_polygons)
        specs = list(osm_specs)
        skipped = 0
        for group in groups.values():
            joined = union_all(group)
            parts = [joined] if joined.geom_type == "Polygon" else list(joined.geoms)
            for polygon in parts:
                duplicate = any(polygon.intersection(osm_polygons[j]).area > .25 * min(polygon.area, osm_polygons[j].area) for j in osm_tree.query(polygon))
                if duplicate:
                    skipped += 1
                    continue
                polygons.append(polygon)
                specs.append({"id": "gsi_" + hashlib.sha256(geometry.key(polygon)).hexdigest()[:20], "source": "国土地理院最適化ベクトルタイル", "tags": {}})
        print(f"GSI/OSM 중복 {skipped}, 결합 {len(polygons)}", flush=True)
        height_path = self.ROOT / "godot_project" / meta["assets"]["heightmap"].removeprefix("res://")
        heights = np.asarray(Image.open(height_path), dtype=np.float32) / 65535
        heights = meta["min_elevation"] + heights * (meta["max_elevation"]-meta["min_elevation"])

        def elevation(x, z):
            u = np.clip((x/geometry.size+.5)*(heights.shape[1]-1), 0, heights.shape[1]-1)
            v = np.clip((z/geometry.size+.5)*(heights.shape[0]-1), 0, heights.shape[0]-1)
            x0, y0 = int(u), int(v)
            x1, y1 = min(x0+1, heights.shape[1]-1), min(y0+1, heights.shape[0]-1)
            return float((heights[y0,x0]*(1-(u-x0))+heights[y0,x1]*(u-x0))*(1-(v-y0))+(heights[y1,x0]*(1-(u-x0))+heights[y1,x1]*(u-x0))*(v-y0))

        buildings = [b for b in old["buildings"] if str(b.get("id", "")).startswith("landmark_")]
        grid = Counter()
        precision = Counter()
        for polygon, spec in zip(polygons, specs):
            center = polygon.centroid
            points = [[round(x,2), round(z,2)] for x,z in list(polygon.exterior.coords)[:-1]]
            height, quality = geometry.height(spec["tags"])
            base = max(elevation(x,z) for x,z in points)
            if base < -2:
                rejected["below_sea_level"] += 1
                continue
            low_x, low_z, high_x, high_z = polygon.bounds
            record = {"id": spec["id"], "source": spec["source"], "height_source": quality, "height": round(height,2), "base_y": round(base,2), "center": [round(center.x,2),round(base+height/2,2),round(center.y,2)], "size": [round(high_x-low_x,2),round(height,2),round(high_z-low_z,2)], "polygon": points, "name": spec["tags"].get("name", "")}
            if polygon.interiors:
                record["holes"] = [[[round(x,2),round(z,2)] for x,z in list(ring.coords)[:-1]] for ring in polygon.interiors]
                record["roof_triangles"] = [[[round(x,2),round(z,2)] for x,z in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(polygon).geoms]
            buildings.append(record)
            precision[quality] += 1
            grid[(int((center.x/geometry.size+.5)*6), int((center.y/geometry.size+.5)*5))] += 1
        fresh_osm = self.read(self.ROOT / "data/raw/buildings/kanmon_straits_buildings_20261003.json")
        buildings, relation_metrics = OsmMultipolygonBuildings().augment(buildings, fresh_osm, meta, elevation)
        precision = Counter(b.get("height_source", "landmark") for b in buildings)
        grid = Counter((int((b["center"][0]/geometry.size+.5)*6), int((b["center"][2]/geometry.size+.5)*5)) for b in buildings)
        out = folder / "buildings_20261003"
        out.mkdir(exist_ok=True)
        asset = out / "buildings_and_roads.json"
        old["buildings"] = buildings
        asset.write_text(json.dumps(old, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        shutil.copy2(folder / "road_metadata.json", out / "road_metadata.json")
        VectorStreamCache(asset).build()
        metrics = {"osm_valid": len(osm_polygons), "gsi_raw_fragments": 371956, "gsi_exact_unique": len(gsi_polygons), "gsi_fragment_groups": len(groups), "gsi_duplicates_with_osm": skipped, "generated_buildings": len(buildings), "height_quality": dict(precision), "rejected": dict(rejected), "grid_6x5": [{"x": x, "z": z, "buildings": count} for (x,z),count in sorted(grid.items())], "roads_preserved": len(old["roads"]), "output": str(asset)}
        metrics.update(relation_metrics)
        (self.ROOT / "results/261003_kanmon_building_generation_metrics.json").write_text(json.dumps(metrics,ensure_ascii=False,indent=2), encoding="utf-8")
        print(json.dumps(metrics,ensure_ascii=False), flush=True)


if __name__ == "__main__":
    KanmonBuildingBuilder().build()
