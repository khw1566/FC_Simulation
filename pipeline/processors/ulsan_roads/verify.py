"""도로 조각 추적, 건물 보존, 공간 배치 해시를 전 범위 확인한다."""
import json
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.build import ROOT, read, digest, save


def verify():
    report = read(ROOT/"results/ulsan_80km_roads/build_report.json")
    stage = ROOT/report["stage"]
    source = ROOT/report["baseline"]["source_path"]
    if digest(source) != report["baseline"]["source_sha256"]:
        raise RuntimeError("기존 벡터 원본의 동시 변경")
    before = read(source)
    after = read(stage/"buildings_and_roads.json")
    preserved = {k:before[k]==after.get(k) for k in before if k not in ("roads","road_count","road_source")}
    assert all(preserved.values()), "비대상 필드 변경"
    original_buildings = len(before.get("buildings",[]))
    del before
    roads = after["roads"]
    ids = {r["id"] for r in roads}
    assert len(ids)==len(roads), "도로 ID 중복"
    assert all(len(r["points"])>=2 and all(abs(p[0])<=40000.01 and abs(p[2])<=40000.01 for p in r["points"]) for r in roads)
    mapping = read(stage/"road_mapping.json")
    assert {rid for m in mapping for rid in m["road_ids"]}==ids
    assert all(m["road_ids"] or m["excluded"] for m in mapping)
    index = read(stage/"vector_stream/index.json")
    path = stage/"buildings_and_roads.json"
    assert index["source_sha256"]==digest(path)
    assert index["source_size"]==path.stat().st_size
    assert index["source_modified"]==int(path.stat().st_mtime)
    cache_ids, counts = set(), {}
    for entry in index["batches"]:
        batch_path = stage/"vector_stream"/entry["file"]
        assert digest(batch_path)==entry["sha256"], str(batch_path)
        kind = entry["kind"]
        counts[kind] = counts.get(kind,0)+entry["count"]
        if kind=="roads":
            batch = read(batch_path)["roads"]
            assert len(batch)==entry["count"]
            for r in batch:
                assert r["id"] not in cache_ids
                cache_ids.add(r["id"])
                assert all((p[0]-entry["center"][0])**2+(p[2]-entry["center"][1])**2 <= (entry["radius"]+.01)**2 for p in r["points"])
    assert cache_ids==ids
    assert counts==index["counts"]
    value = {"passed":True,"revision":report["revision"],"runtime_roads":len(roads),
             "source_way_mapping":len(mapping),"preserved_fields":preserved,
             "preserved_building_count":original_buildings,"cache_counts":counts,
             "verified_batch_hashes":len(index["batches"]),"geometry_bounds_m":40000,
             "full_world_run":False}
    save(stage/"verification.json",value)
    save(ROOT/"results/ulsan_80km_roads/verification.json",value)
    print(json.dumps(value,ensure_ascii=False),flush=True)


if __name__=="__main__":
    verify()
