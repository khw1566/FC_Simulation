"""완료된 원본을 전용 리비전에 변환하고 기존 건물을 보존한다."""
import hashlib
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ulsan_roads import geometry, audit

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    temp = path.with_suffix(".tmp")
    with temp.open("w",encoding="utf-8") as stream:
        json.dump(value,stream,ensure_ascii=False,separators=(",",":"))
    temp.replace(path)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name,path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build():
    raw_folder = ROOT/"data/raw/ulsan_metro_80km/highways"
    progress = read(raw_folder/"progress.json")
    if not progress.get("coverage_complete"):
        raise RuntimeError("전 범위 수집이 완료되지 않았습니다")
    config = read(ROOT/"config/ulsan_metro_80km.json")
    if progress["bbox"] != config["bbox"]:
        raise RuntimeError("수집 경계와 지도 설정 불일치")
    meta_path = ROOT/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json"
    meta = read(meta_path)
    source = ROOT/"godot_project"/meta["assets"]["buildings_roads"].removeprefix("res://")
    snapshot = {"source_path":str(source.relative_to(ROOT)),"source_sha256":digest(source),
                "meta_sha256":digest(meta_path),"config_sha256":digest(ROOT/"config/ulsan_metro_80km.json")}
    names = ["full_80km"] if progress["coverage_mode"] == "full_bbox" else sorted(progress["completed"])
    ways = {}
    for name in names:
        path = raw_folder/f"{name}.json"
        if digest(path) != progress["completed"][name]["sha256"]:
            raise RuntimeError(f"원본 해시 불일치: {name}")
        for way in read(path)["elements"]:
            prior = ways.get(way["id"])
            if prior is None or way.get("version",0) > prior.get("version",0):
                ways[way["id"]] = way
    roads, excluded, mapping = [], [], []
    for way in sorted(ways.values(),key=lambda w:w["id"]):
        converted, reason = geometry.convert(way,config)
        roads.extend(converted)
        mapping.append({"osm_id":way["id"],"road_ids":[r["id"] for r in converted],"excluded":reason})
        if reason:
            excluded.append({"osm_id":way["id"],"highway":way.get("tags",{}).get("highway"),"reason":reason})
    if any(item["reason"] == "invalid_geometry" or item["reason"].startswith("unsupported_highway") for item in excluded):
        save(ROOT/"results/ulsan_80km_roads/unsupported.json",excluded)
        raise RuntimeError("설명되지 않은 도로 유형 또는 잘못된 좌표가 있습니다")
    revision = hashlib.sha256(json.dumps([snapshot,progress["completed"],roads],sort_keys=True).encode()).hexdigest()[:16]
    stage = ROOT/"data/processed/ulsan_metro_80km/roads"/revision
    stage.mkdir(parents=True,exist_ok=True)
    print(f"변환 {len(ways)} ways -> {len(roads)} roads; revision {revision}",flush=True)
    original = read(source)
    before = audit.summarize(original["roads"],config)
    after = audit.summarize(roads,config)
    audit.write(ROOT/"results/ulsan_80km_roads",before,after)
    original["roads"] = roads
    original["road_count"] = len(roads)
    original["road_source"] = {"provider":"OpenStreetMap", "license":"ODbL-1.0", "attribution":"OpenStreetMap contributors",
                               "revision":revision,"bbox":config["bbox"],"coverage_mode":progress["coverage_mode"],
                               "coverage_complete":True,"raw_ways":len(ways)}
    save(stage/"buildings_and_roads.json",original)
    del original, ways
    cache_module = load_module("road_vector_stream_cache",ROOT/"pipeline/processors/vector_stream_cache.py")
    optimizer_module = load_module("road_building_optimizer",ROOT/"pipeline/processors/building_optimizer.py")
    cache_module.VectorStreamCache(stage/"buildings_and_roads.json",optimizer_module.BuildingOptimizer()).build()
    index = read(stage/"vector_stream/index.json")
    if index["counts"]["roads"] != len(roads):
        raise RuntimeError("공간 캐시 도로 수 불일치")
    report = {"revision":revision,"stage":str(stage.relative_to(ROOT)),"baseline":snapshot,
              "source_ways":len(mapping),"runtime_roads":len(roads),"excluded":dict(Counter(e["reason"] for e in excluded)),
              "width_basis":dict(Counter(r["width_basis"] for r in roads)),
              "bridges":sum(r["bridge"] for r in roads),"tunnels":sum(r["tunnel"] for r in roads),
              "cache_counts":index["counts"],"source_sha256":index["source_sha256"],
              "raw_collection":progress,"coverage_summary":{k:v for k,v in after.items() if k!="cell_length_m"}}
    save(stage/"road_mapping.json",mapping)
    save(stage/"excluded.json",excluded)
    save(stage/"build_report.json",report)
    save(ROOT/"results/ulsan_80km_roads/build_report.json",report)
    print(json.dumps({k:report[k] for k in ("revision","runtime_roads","excluded","cache_counts")}),flush=True)


if __name__ == "__main__":
    build()
