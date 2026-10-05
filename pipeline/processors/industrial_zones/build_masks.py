"""사용자 지정 공단 다각형을 지도 좌표의 구역·제외·허용 마스크로 변환."""
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simple_maps.publish import atomic, merge


class IndustrialZoneMaskBuilder:
    def run(self):
        config = json.loads((ROOT / "config/industrial_zones.json").read_text(encoding="utf-8"))
        meta = json.loads((ROOT / f"godot_project/assets/maps/{config['map_id']}/map_meta.json").read_text(encoding="utf-8"))
        source = ROOT / config["regions_path"]
        regions = json.loads(source.read_text(encoding="utf-8"))
        size, bbox = int(config["resolution"]), meta["bbox"]
        if not 256 <= size <= 8192:
            raise ValueError("마스크 해상도 범위는 256~8192입니다")
        output = ROOT / f"godot_project/assets/generated/industrial_zones/{config['map_id']}"
        output.mkdir(parents=True, exist_ok=True)
        ids = np.zeros((size, size), dtype=np.uint16)
        used, catalog = set(), []
        for feature in regions["features"]:
            properties = feature["properties"]
            zone_id = int(properties["zone_id"])
            if not 1 <= zone_id <= 65535 or zone_id in used:
                raise ValueError("zone_id는 중복 없는 1~65535 정수여야 합니다")
            used.add(zone_id)
            profile = properties.get("profile", "general_factory")
            if profile not in config["profiles"]:
                raise ValueError("알 수 없는 공단 프로필: " + profile)
            geometry = feature["geometry"]
            if geometry["type"] not in ("Polygon", "MultiPolygon"):
                raise ValueError("구역 형상은 Polygon 또는 MultiPolygon이어야 합니다")
            polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
            layer = Image.new("L", (size, size))
            draw = ImageDraw.Draw(layer)
            for polygon in polygons:
                for index, ring in enumerate(polygon):
                    if len(ring) < 4 or ring[0] != ring[-1]:
                        raise ValueError("다각형은 3개 이상의 점과 닫힌 외곽선이 필요합니다")
                    pixels = []
                    for lon, lat in ring:
                        if not (bbox["west"] <= lon <= bbox["east"] and bbox["south"] <= lat <= bbox["north"]):
                            raise ValueError("공단 경계가 지도 영역을 벗어났습니다")
                        pixels.append(((lon-bbox["west"])/(bbox["east"]-bbox["west"])*(size-1), (bbox["north"]-lat)/(bbox["north"]-bbox["south"])*(size-1)))
                    draw.polygon(pixels, fill=255 if index == 0 else 0)
            selected = np.asarray(layer) != 0
            if np.any((ids != 0) & selected):
                raise ValueError("공단 구역이 서로 겹칩니다. 경계를 조정하세요")
            ids[selected] = zone_id
            catalog.append({"zone_id":zone_id, "name_ko":properties.get("name_ko", f"구역 {zone_id}"),
                            "profile":profile, "seed":int(properties.get("seed", config["seed"]+zone_id)),
                            "status":properties.get("status", "draft"), "mask_pixels":int(selected.sum())})
        water_path = ROOT / "godot_project" / meta["assets"]["watermask"].removeprefix("res://")
        with Image.open(water_path) as water:
            excluded = water.convert("L").resize((size, size), Image.Resampling.BILINEAR).point(lambda p: 255 if p >= 64 else 0)
        buffer = math.ceil(float(config["water_buffer_m"]) / (meta["world_size_meters"] / size))
        if buffer:
            excluded = excluded.filter(ImageFilter.MaxFilter(buffer*2+1))
        ids_image = Image.fromarray(ids)
        ids_image.save(output / "zone_ids.png")
        excluded.save(output / "excluded_water.png")
        confirmed = np.isin(ids, [z["zone_id"] for z in catalog if z["status"] == "confirmed"])
        allowed = (ids != 0) & confirmed & (np.asarray(excluded) == 0)
        Image.fromarray((allowed*255).astype(np.uint8)).save(output / "allowed.png")
        atomic(output / "regions.json", {"version":1, "bbox":bbox, "world_size_meters":meta["world_size_meters"],
               "source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(), "zones":catalog,
               "state":"awaiting_region_selection" if not catalog else "masked",
               "allowed_pixels":int(allowed.sum()), "road_generation_enabled":False,
               "note_ko":"allowed은 confirmed 구역에서 수계만 제외한 1차 마스크. 기존 도로·철도·건물과 경사 검사는 후속 단계에서 추가한다."})
        entries = {}
        for path in output.iterdir():
            if path.name == "manifest.json":
                continue
            if path.suffix == ".png":
                resolution = {"width":size, "height":size, "meters_per_pixel":meta["world_size_meters"]/size}
            else:
                resolution = {"type":"zone_catalog", "count":len(catalog)}
            entries[f"industrial_zones/{config['map_id']}/{path.name}"] = {
                "file_path":"res://"+path.relative_to(ROOT/"godot_project").as_posix(),
                "sha256":hashlib.sha256(path.read_bytes()).hexdigest(), "bbox":bbox,
                "elevation_min":None, "elevation_max":None, "resolution":resolution, "type":"industrial_zone_mask"}
        atomic(output / "manifest.json", {"version":1, "assets":entries})
        merge(ROOT / "godot_project/assets/generated/manifest.json", entries)
        print(json.dumps({"zones":len(catalog), "allowed_pixels":int(allowed.sum()), "resolution":size}, ensure_ascii=False))


if __name__ == "__main__":
    IndustrialZoneMaskBuilder().run()
