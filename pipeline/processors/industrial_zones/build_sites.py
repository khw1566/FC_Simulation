"""OSM 산업 용지 경계를 공단 구역으로 삼아 도로 분할·용도 구역·설비 배치 데이터를 생성한다."""
import hashlib
import json
import math
import random
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import shape, mapping
from shapely.ops import transform

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from industrial_zones.site_inputs import IndustrialSiteInputs
from industrial_zones.landuse_zones import LanduseZoneBuilder
from industrial_zones.asset_catalog import load_catalog
from industrial_zones.block_divider import IndustrialBlockDivider
from industrial_zones.block_signals import IndustrialBlockSignals
from industrial_zones.district_planner import IndustrialDistrictPlanner
from industrial_zones.district_fillers import IndustrialDistrictFiller
from industrial_zones.district_links import IndustrialDistrictLinker
from industrial_zones.build_masks import IndustrialZoneMaskBuilder
from simple_maps.publish import atomic, merge

# 배치도에서 용도를 흑백 명도로 구분한다.
DISTRICT_SHADES = {"tank_farm": 205, "process": 170, "factory": 135, "shipyard": 235, "logistics": 100, "utility": 75}


class IndustrialSiteBuilder:
    def run(self):
        config = IndustrialSiteInputs.read(ROOT / "config/industrial_zones.json")
        regions_path = ROOT / config["regions_path"]
        source = IndustrialSiteInputs.read(regions_path)
        landuse = ROOT / config.get("landuse_source", "")
        # 경계 편집기에서 고친 구역을 덮어쓰지 않도록, OSM 변환은 처음 한 번 또는 --rebuild-zones 지정 시에만 한다.
        from_osm = all(f.get("properties", {}).get("source") == "osm_landuse_industrial" for f in source["features"]) and source["features"]
        if config.get("zone_source") == "osm_landuse" and (not from_osm or "--rebuild-zones" in sys.argv):
            if not landuse.is_file():
                raise RuntimeError("산업 용지 경계가 없습니다. pipeline/collectors/industrial_landuse_collector.py를 먼저 실행하세요")
            meta = IndustrialSiteInputs.read(ROOT / f"godot_project/assets/maps/{config['map_id']}/map_meta.json")
            builder = LanduseZoneBuilder(meta)
            builder.MIN_ZONE_AREA_M2 = float(config.get("zone_min_area_m2", builder.MIN_ZONE_AREA_M2))
            source = {**source, "features": builder.build(landuse)}
            atomic(regions_path, source)
        inputs = IndustrialSiteInputs(ROOT, config)
        catalog = load_catalog(ROOT)
        signals = IndustrialBlockSignals(inputs)
        planner = IndustrialDistrictPlanner(inputs, random.Random(config["seed"]))
        sites = []
        for feature in source["features"]:
            props = feature["properties"]
            if props.get("status") != "confirmed":
                continue
            geometry = transform(lambda lon, lat, z=None: inputs.project([lon, lat]), shape(feature["geometry"]))
            if not geometry.is_valid:
                geometry = geometry.buffer(0)
            site = self.generate(geometry, inputs, config, catalog, signals, planner, props)
            site.update(name_ko=props["name_ko"], geometry=geometry, zone_id=props["zone_id"])
            sites.append(site)
            print("SITE", props["zone_id"], site["profile"], "blocks", len(site["records"]), "roads", len(site["roads"]),
                  "assets", len(site["placements"]), flush=True)
        if not sites:
            raise RuntimeError("생성할 확정 구역이 없습니다")
        self.publish(sites, inputs, config, regions_path)

    def generate(self, geometry, inputs, config, catalog, signals, planner, props):
        zone_id = int(props["zone_id"])
        rng = random.Random(int(props.get("seed", config["seed"] + zone_id)))
        profile_name = props.get("profile", "general_factory")
        profile = config["profiles"][profile_name]
        # 구역 안의 기존 범용 건물은 절차 설비로 대체하므로 보호하지 않는다.
        land = inputs.safe_geometry(geometry, include_buildings=False)
        layout = IndustrialBlockDivider(inputs, profile, rng).build(geometry, land)
        planner.rng = rng
        records, zone_profile = planner.plan(layout["blocks"], profile_name, [signals.measure(b) for b in layout["blocks"]])
        filler = IndustrialDistrictFiller(inputs, catalog, rng, zone_id, planner)
        placements = []
        for record in records:
            placements.extend(filler.fill(record, len(placements)))
        placements.extend(IndustrialDistrictLinker(inputs, catalog, zone_id).link(records, placements))
        return {"roads": layout["roads"], "records": records, "placements": placements, "land": land,
                "profile": zone_profile, "existing_road_count": layout["existing_road_count"]}

    def publish(self, sites, inputs, config, regions_path):
        folder = ROOT / f"godot_project/assets/generated/industrial_zones/{config['map_id']}"
        folder.mkdir(parents=True, exist_ok=True)
        IndustrialZoneMaskBuilder().run()
        allowed = Image.new("L", (inputs.resolution, inputs.resolution))
        zones, roads, placements, parcels, suppression = [], [], [], [], []
        for site in sites:
            inputs.rasterize(site["land"], allowed)
            center = site["geometry"].centroid
            districts = {}
            for record in site["records"]:
                districts[record["district"]] = districts.get(record["district"], 0) + 1
            zones.append({"zone_id": site["zone_id"], "name_ko": site["name_ko"], "profile": site["profile"],
                          "world_polygon": mapping(site["geometry"]), "center_xz": [center.x, center.y],
                          "connection": {"existing_roads_used": site["existing_road_count"]}, "connected_nodes": len(site["roads"]),
                          "component_count": 1, "preserve_existing_buildings": False, "replace_existing_buildings": True,
                          "district_blocks": districts, "asset_count": len(site["placements"]), "road_count": len(site["roads"])})
            for road in site["roads"]:
                roads.append({**road, "id": f"zone_{site['zone_id']}_" + road["id"], "zone_id": site["zone_id"]})
            placements.extend(site["placements"])
            for record in site["records"]:
                parcels.append({"zone_id": site["zone_id"], "parcel_id": record["block_id"], "district": record["district"],
                                "coast_ratio": round(record["coast_ratio"], 3), "geometry": mapping(record["geometry"]),
                                "area_m2": round(record["area_m2"], 1)})
            outline = site["geometry"].simplify(10)
            polygons = [outline] if outline.geom_type == "Polygon" else list(outline.geoms)
            for polygon in polygons:
                suppression.append({"zone_id": site["zone_id"], "bounds": [round(v, 1) for v in polygon.bounds],
                                    "ring_xz": [[round(x, 1), round(z, 1)] for x, z in polygon.exterior.coords[:-1]]})
        allowed.save(folder / "allowed.png")
        Image.fromarray(255 - np.asarray(allowed)).save(folder / "excluded_all.png")
        atomic(folder / "roads.json", {"version": 2, "map_id": config["map_id"], "roads": roads, "zones": zones})
        atomic(folder / "parcels.json", {"version": 2, "parcels": parcels})
        atomic(folder / "building_suppression.json", {"version": 1, "map_id": config["map_id"],
               "policy": "공단 구역 안의 범용 건물은 절차 생성 설비로 대체", "zones": suppression})
        atomic(folder / "placements.json", {"version": 2, "map_id": config["map_id"], "settings": {
               "enabled": True, "detail_distance_m": 2600, "render_distance_m": 9000, "chunk_size_m": 600, "creation_budget_per_frame": 2},
               "zones": zones, "placements": placements, "roads_path": "res://" + (folder / "roads.json").relative_to(ROOT / "godot_project").as_posix(),
               "regions_source_sha256": hashlib.sha256(regions_path.read_bytes()).hexdigest(),
               "source_policy": "OSM 산업 용지 경계와 고정 seed. 구역 안 범용 건물은 대체하고 철도·수계·공항·문화유산은 보존."})
        region_catalog = IndustrialSiteInputs.read(folder / "regions.json")
        region_catalog.update(road_generation_enabled=True, allowed_pixels=int((np.asarray(allowed) > 0).sum()),
                              note_ko="OSM 산업 용지 구역에서 수계·급경사·철도·공항·문화유산을 제외한 배치 허용 영역")
        atomic(folder / "regions.json", region_catalog)
        self.preview(folder, sites)
        entries = {}
        for path in folder.iterdir():
            if path.name == "manifest.json":
                continue
            resolution = {"type": "procedural_layout"}
            if path.suffix == ".png":
                with Image.open(path) as image:
                    resolution = {"width": image.width, "height": image.height}
            entries[f"industrial_zones/{config['map_id']}/{path.name}"] = {
                "file_path": "res://" + path.relative_to(ROOT / "godot_project").as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "bbox": inputs.bbox, "elevation_min": min(p["foundation_bottom_y"] for p in placements),
                "elevation_max": max(p["position"][1] + p["aabb_max_m"][1] * p["scale"] for p in placements), "resolution": resolution,
                "type": "industrial_zone_layout"}
        atomic(folder / "manifest.json", {"version": 2, "assets": entries})
        merge(ROOT / "godot_project/assets/generated/manifest.json", entries)
        kinds = {}
        for placement in placements:
            kinds[placement["district"]] = kinds.get(placement["district"], 0) + 1
        report = {"zones": len(zones), "roads": len(roads), "assets": len(placements), "blocks": len(parcels), "assets_by_district": kinds,
                  "method": "OSM 산업 용지 구역, 기존 도로+재귀 분할 도로로 블록 분할, 기존 건물 단서 기반 용도 지정, 용도별 줄 배치, 저장고-공정 파이프랙·송전 연결"}
        atomic(ROOT / f"results/{datetime.now():%y%m%d}_IndustrialSitesGeneration.json", report)
        print(json.dumps(report, ensure_ascii=False), flush=True)

    @staticmethod
    def preview(folder, sites, cell=600, columns=6):
        rows = math.ceil(len(sites) / columns)
        image = Image.new("L", (cell * columns, cell * rows), 25)
        draw = ImageDraw.Draw(image)
        for index, site in enumerate(sites):
            ox, oy = (index % columns) * cell, (index // columns) * cell
            bounds = site["geometry"].bounds
            size = max(bounds[2] - bounds[0], bounds[3] - bounds[1]) or 1
            def pixel(p):
                return (ox + 15 + (p[0] - bounds[0]) / size * (cell - 30), oy + 40 + (p[1] - bounds[1]) / size * (cell - 55))
            draw.text((ox + 15, oy + 12), f"Zone {site['zone_id']} / {site['profile']} / {len(site['placements'])} assets", fill=255)
            for record in site["records"]:
                draw.polygon([pixel(p) for p in record["geometry"].exterior.coords], fill=DISTRICT_SHADES[record["district"]] // 3)
            for road in site["roads"]:
                draw.line([pixel(p) for p in road["points_xz"]], fill=255, width=2)
            for placement in site["placements"]:
                draw.polygon([pixel(p) for p in placement["footprint_xz"]], fill=DISTRICT_SHADES.get(placement["district"], 150))
        image.save(folder / "layout_preview.png")


if __name__ == "__main__":
    IndustrialSiteBuilder().run()
