"""울산 60km 기존 자료와 80km 외곽 셀을 80km 런타임 좌표계로 병합한다."""

import hashlib
import json
import sys
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from pipeline.processors.vworld_building_processor import VWorldBuildingProcessor


MAP_ID = "ulsan_metro_80km"


def _project_road_point(point, source, target):
    if len(point) < 3:
        return point
    x, y, z = map(float, point[:3])
    source_size = float(source["world_size_meters"])
    target_size = float(target["world_size_meters"])
    lon = source["bbox"]["west"] + (x / source_size + 0.5) * (
        source["bbox"]["east"] - source["bbox"]["west"]
    )
    lat = source["bbox"]["north"] - (z / source_size + 0.5) * (
        source["bbox"]["north"] - source["bbox"]["south"]
    )
    tx = (lon - target["bbox"]["west"]) / (
        target["bbox"]["east"] - target["bbox"]["west"]
    )
    tz = (target["bbox"]["north"] - lat) / (
        target["bbox"]["north"] - target["bbox"]["south"]
    )
    return [round((tx - 0.5) * target_size, 2), round(y, 2), round((tz - 0.5) * target_size, 2)]


def _load_roads(source_config, target_config, source_path, active_path=None):
    # 도로 전용 갱신 이후에는 활성 80km 선형을 보존한다.
    if active_path is not None and active_path.is_file():
        active = json.loads(active_path.read_text(encoding="utf-8"))
        if active.get("road_source", {}).get("coverage_complete"):
            return active.get("roads", []), active.get("tunnels", []), active["road_source"]
    source_data = json.loads(source_path.read_text(encoding="utf-8"))
    roads = source_data.get("roads", [])
    for road in roads:
        road["points"] = [
            _project_road_point(point, source_config, target_config)
            for point in road.get("points", [])
        ]
    return roads, source_data.get("tunnels", []), source_data.get("road_source")


def _collect_features(core_cache, outer_cache, expected_outer_cells):
    outer_manifest = json.loads(
        (outer_cache / "manifest_progress.json").read_text(encoding="utf-8-sig")
    )
    completed = set(outer_manifest.get("completed_cells", []))
    missing = sorted(set(expected_outer_cells) - completed)
    if missing:
        raise RuntimeError(f"80km 외곽 셀이 미완료 상태임: {len(missing)}개")

    seen = set()
    features = []
    source_counts = {"core_60km": 0, "outer_80km": 0}
    cache_files = [
        (path, "core_60km") for path in sorted(core_cache.glob("phase*.json"))
    ] + [
        (outer_cache / f"{cell_id}.json", "outer_80km")
        for cell_id in sorted(expected_outer_cells)
    ]
    for path, source_name in cache_files:
        if not path.is_file():
            raise FileNotFoundError(f"수집 완료 목록의 셀 캐시가 없음: {path.name}")
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        for feature in payload.get("features", []):
            building_id = str(feature.get("properties", {}).get("bd_mgt_sn", "")).strip()
            if building_id and building_id in seen:
                continue
            if building_id:
                seen.add(building_id)
            features.append(feature)
            source_counts[source_name] += 1
    return features, source_counts, len(cache_files)


def merge_ulsan_80km_buildings():
    maps_root = PROJECT_ROOT / "godot_project/assets/maps"
    core_cache = maps_root / "ulsan_metro_60km/buildings_cache"
    outer_cache = maps_root / f"{MAP_ID}/buildings_cache"
    core_config = json.loads((PROJECT_ROOT / "config/ulsan_metro_60km.json").read_text(encoding="utf-8"))
    target_config_path = PROJECT_ROOT / f"config/{MAP_ID}.json"
    target_config = json.loads(target_config_path.read_text(encoding="utf-8"))
    cells = _build_expected_cells(target_config)
    features, source_counts, cache_count = _collect_features(
        core_cache, outer_cache, {cell["cell_id"] for cell in cells}
    )

    raw_dir = PROJECT_ROOT / "data/raw/ulsan_metro_80km/buildings"
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_path = raw_dir / "vworld_core_and_outer_buildings.json"
    with raw_path.open("w", encoding="utf-8") as output:
        json.dump({"type": "FeatureCollection", "features": features}, output, ensure_ascii=False)

    map_meta_path = maps_root / f"{MAP_ID}/map_meta.json"
    map_meta = json.loads(map_meta_path.read_text(encoding="utf-8"))
    dem_path = PROJECT_ROOT / map_meta["assets"]["heightmap"].replace("res://", "")
    water_path = PROJECT_ROOT / map_meta["assets"]["watermask"].replace("res://", "")
    roads, tunnels, road_source = _load_roads(
        core_config,
        target_config,
        maps_root / "ulsan_metro_60km/buildings_and_roads.json",
        PROJECT_ROOT / "godot_project" / map_meta["assets"]["buildings_roads"].replace("res://", ""),
    )
    output_path = maps_root / f"{MAP_ID}/buildings_and_roads.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps({"roads": roads, "tunnels": tunnels, "road_source": road_source}, ensure_ascii=False),
        encoding="utf-8",
    )

    processor = VWorldBuildingProcessor(str(target_config_path))
    processor.process_vworld_buildings(
        str(raw_path), str(dem_path), str(output_path), str(water_path)
    )
    runtime = json.loads(output_path.read_text(encoding="utf-8"))
    digest = hashlib.sha256(output_path.read_bytes()).hexdigest()
    entry = {
        "file_path": f"res://assets/maps/{MAP_ID}/buildings_and_roads.json",
        "type": "buildings_and_roads", "format": "JSON", "sha256": digest,
        "size_bytes": output_path.stat().st_size, "bbox": target_config["bbox"],
        "elevation": {
            "min_meters": target_config["elevation_range"]["min_meters"],
            "max_meters": target_config["elevation_range"]["max_meters"],
        },
        "resolution": {
            "type": "vector", "buildings": runtime["building_count"],
            "roads": runtime["road_count"], "source_cache_files": cache_count,
        },
    }
    map_manifest_path = maps_root / f"{MAP_ID}/manifest.json"
    map_manifest = json.loads(map_manifest_path.read_text(encoding="utf-8-sig"))
    map_manifest.setdefault("assets", {})["buildings_and_roads.json"] = entry
    map_manifest["last_updated"] = datetime.now().astimezone().isoformat()
    map_manifest_path.write_text(json.dumps(map_manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    generated_path = PROJECT_ROOT / "godot_project/assets/generated/manifest.json"
    generated = json.loads(generated_path.read_text(encoding="utf-8-sig"))
    generated.setdefault("assets", {})[f"{MAP_ID}_buildings_and_roads"] = {
        **entry,
        "file_path": str(output_path.resolve()),
        "metadata": {"source_counts": source_counts, **entry["resolution"]},
    }
    generated["last_updated"] = datetime.now().astimezone().isoformat()
    generated_path.write_text(json.dumps(generated, ensure_ascii=False, indent=2), encoding="utf-8")

    map_meta["assets"]["buildings_roads"] = f"res://assets/maps/{MAP_ID}/buildings_and_roads.json"
    map_meta["coverage"]["detailed_vectors_source"] = "VWorld LT_C_SPBD: 울산 60km 코어 + 80km 외곽"
    map_meta["coverage"]["outer_buildings_collected"] = True
    map_meta["coverage"]["outer_buildings_roads_collected"] = bool(
        map_meta["coverage"].get("roads", {}).get("coverage_complete", False)
    )
    map_meta_path.write_text(json.dumps(map_meta, ensure_ascii=False, indent=2), encoding="utf-8")

    result = {
        "map_id": MAP_ID, "cache_files": cache_count,
        "input_unique_features": len(features), "source_counts": source_counts,
        "runtime_buildings": runtime["building_count"], "runtime_roads": runtime["road_count"],
        "sha256": digest, "size_bytes": output_path.stat().st_size,
        "runtime_path": entry["file_path"],
    }
    report_path = PROJECT_ROOT / f"results/{datetime.now().astimezone():%y%m%d}_Ulsan80kmBuildingMerge.json"
    report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    from pipeline.processors.vector_stream_cache import VectorStreamCache
    from pipeline.processors.building_optimizer import BuildingOptimizer
    VectorStreamCache(output_path, BuildingOptimizer()).build()
    print(json.dumps(result, ensure_ascii=False), flush=True)


def _build_expected_cells(config):
    from pipeline.collectors.ulsan_80km_building_collector import Ulsan80kmBuildingCollector
    collector = object.__new__(Ulsan80kmBuildingCollector)
    collector.config = config
    return collector.outer_cells()


if __name__ == "__main__":
    merge_ulsan_80km_buildings()
