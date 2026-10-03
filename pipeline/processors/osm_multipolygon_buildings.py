"""OSM 복합 건물의 외곽과 중정을 연결하고 기존 중복 외곽선을 대체한다."""
import json
from pathlib import Path
from shapely import STRtree, constrained_delaunay_triangles
from shapely.geometry import LineString, Polygon
from shapely.ops import polygonize, unary_union
from kanmon_building_geometry import KanmonBuildingGeometry
from building_source_store import BuildingSourceStore


class OsmMultipolygonBuildings:
    def augment(self, buildings, raw, meta, elevation):
        geometry = KanmonBuildingGeometry(meta)
        nodes = {e["id"]: [e["lon"], e["lat"]] for e in raw["elements"] if e["type"] == "node"}
        ways = {e["id"]: e for e in raw["elements"] if e["type"] == "way"}
        shapes = [Polygon(b["polygon"]) for b in buildings]
        tree = STRtree(shapes)
        removed, added = set(), []
        for relation in raw["elements"]:
            tags = relation.get("tags", {})
            if relation["type"] != "relation" or tags.get("building") in (None, "no"):
                continue
            lines = {"outer": [], "inner": []}
            for member in relation.get("members", []):
                if member["type"] != "way" or member["ref"] not in ways:
                    continue
                ids = ways[member["ref"]].get("nodes", [])
                if len(ids) < 2 or any(i not in nodes for i in ids):
                    continue
                lines["inner" if member.get("role") == "inner" else "outer"].append(LineString([nodes[i] for i in ids]))
            outers = list(polygonize(unary_union(lines["outer"])))
            inners = list(polygonize(unary_union(lines["inner"])))
            for part, outer in enumerate(outers):
                rings = [list(outer.exterior.coords)] + [list(inner.exterior.coords) for inner in inners if outer.covers(inner.representative_point())]
                for shape in geometry.polygons(rings):
                    for i in tree.query(shape):
                        if shape.intersection(shapes[i]).area > .25 * min(shape.area, shapes[i].area):
                            removed.add(int(i))
                    points = [[round(x,2),round(z,2)] for x,z in list(shape.exterior.coords)[:-1]]
                    height, quality = geometry.height(tags)
                    base = max(elevation(x,z) for x,z in points)
                    center = shape.centroid
                    x0,z0,x1,z1 = shape.bounds
                    b = {"id": f"osm_relation_{relation['id']}_{part}", "source": "OpenStreetMap", "height_source": quality, "height": round(height,2), "base_y": round(base,2), "center": [round(center.x,2),round(base+height/2,2),round(center.y,2)], "size": [round(x1-x0,2),round(height,2),round(z1-z0,2)], "polygon": points, "name": tags.get("name", "")}
                    if shape.interiors:
                        b["holes"] = [[[round(x,2),round(z,2)] for x,z in list(r.coords)[:-1]] for r in shape.interiors]
                        b["roof_triangles"] = [[[round(x,2),round(z,2)] for x,z in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(shape).geoms]
                    added.append(b)
        return [b for i,b in enumerate(buildings) if i not in removed] + added, {"relation_polygons": len(added), "duplicate_polygons_replaced": len(removed)}


if __name__ == "__main__":
    import numpy as np
    from PIL import Image
    from collections import Counter
    from vector_stream_cache import VectorStreamCache
    root = Path(__file__).resolve().parents[2]
    folder = root / "godot_project/assets/maps/kanmon_straits"
    meta = json.loads((folder/"map_meta.json").read_text(encoding="utf-8-sig"))
    asset = folder/"buildings_20261003/buildings_and_roads.json"
    data = json.loads(asset.read_text(encoding="utf-8"))
    raw = BuildingSourceStore.read(root/"data/raw/buildings/kanmon_straits_buildings_20261003.json")
    image = np.asarray(Image.open(root/"godot_project"/meta["assets"]["heightmap"].removeprefix("res://"))) / 65535
    def elevation(x,z):
        ix = int(np.clip((x/meta["world_size_meters"]+.5)*(image.shape[1]-1),0,image.shape[1]-1))
        iz = int(np.clip((z/meta["world_size_meters"]+.5)*(image.shape[0]-1),0,image.shape[0]-1))
        return float(meta["min_elevation"]+image[iz,ix]*(meta["max_elevation"]-meta["min_elevation"]))
    data["buildings"], metrics = OsmMultipolygonBuildings().augment(data["buildings"], raw, meta, elevation)
    asset.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
    VectorStreamCache(asset).build()
    metric_path = root/"results/261003_kanmon_building_generation_metrics.json"
    summary = json.loads(metric_path.read_text(encoding="utf-8"))
    summary.update(metrics)
    summary["generated_buildings"] = len(data["buildings"])
    summary["height_quality"] = dict(Counter(b.get("height_source","landmark") for b in data["buildings"]))
    metric_path.write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    print(metrics, flush=True)
