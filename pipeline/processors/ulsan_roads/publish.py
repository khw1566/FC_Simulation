"""검증된 리비전을 배치하고 지도 참조를 마지막에 전환한다."""
import json
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.build import ROOT, read, digest, save


def guarded_merge(path, entries):
    before = path.read_bytes()
    doc = json.loads(before)
    doc.setdefault("assets",{}).update(entries)
    temp = path.with_name(path.name+f".roads_{os.getpid()}.tmp")
    temp.write_text(json.dumps(doc,ensure_ascii=False,indent=2),encoding="utf-8")
    if path.read_bytes()!=before:
        temp.unlink()
        raise RuntimeError(f"공유 매니페스트 동시 변경: {path}")
    temp.replace(path)


def publish():
    report = read(ROOT/"results/ulsan_80km_roads/build_report.json")
    stage = ROOT/report["stage"]
    verification = read(stage/"verification.json")
    if not verification["passed"] or verification["revision"]!=report["revision"]:
        raise RuntimeError("현재 리비전 검증이 필요합니다")
    map_folder = ROOT/"godot_project/assets/maps/ulsan_metro_80km"
    meta_path = map_folder/"map_meta.json"
    meta_before = meta_path.read_bytes()
    meta = json.loads(meta_before)
    if digest(meta_path)!=report["baseline"]["meta_sha256"]:
        raise RuntimeError("지도 설정이 변경되어 재검토가 필요합니다")
    if digest(ROOT/report["baseline"]["source_path"])!=report["baseline"]["source_sha256"]:
        raise RuntimeError("원본 벡터가 변경되어 다시 생성해야 합니다")
    destination = map_folder/"road_revisions"/report["revision"]
    if destination.exists():
        if digest(destination/"buildings_and_roads.json")!=report["source_sha256"]:
            raise RuntimeError("기존 리비전 경로가 다른 데이터입니다")
    else:
        destination.parent.mkdir(parents=True,exist_ok=True)
        temporary = destination.with_name(destination.name+".pending")
        if temporary.exists():
            raise RuntimeError(f"미완료 게시 경로를 보존합니다: {temporary}")
        shutil.copytree(stage,temporary,copy_function=shutil.copy2)
        temporary.rename(destination)
    uri = "res://"+destination.relative_to(ROOT/"godot_project").as_posix()+"/"
    # copy2로 원본 수정 시각을 보존하므로 스트리머의 크기·시각 검사와 일치한다.
    index = read(destination/"vector_stream/index.json")
    assert index["source_modified"]==int((destination/"buildings_and_roads.json").stat().st_mtime)
    entries = {}
    for name, resolution in (("buildings_and_roads.json",{"type":"vector","buildings":verification["preserved_building_count"],"roads":report["runtime_roads"]}),
                             ("vector_stream/index.json",{"type":"spatial_vector_batches", "batches":len(index["batches"]),"counts":index["counts"]}),
                             ("road_mapping.json",{"type":"source_way_mapping","ways":report["source_ways"]}),
                             ("excluded.json",{"type":"excluded_source_ways"}),
                             ("build_report.json",{"type":"road_build_report"}),
                             ("verification.json",{"type":"road_verification"})):
        path = destination/name
        entries[f"ulsan80_roads/{report['revision']}/{name}"] = {
            "file_path":uri+name,"sha256":digest(path),"size_bytes":path.stat().st_size,
            "bbox":meta["bbox"],"elevation":{"min_meters":meta["min_elevation"],"max_meters":meta["max_elevation"]},
            "elevation_min":meta["min_elevation"],"elevation_max":meta["max_elevation"],
            "resolution":resolution,"metadata":{"source":"OpenStreetMap","license":"ODbL-1.0","revision":report["revision"],"batch_hashes":"vector_stream/index.json"}}
    save(destination/"manifest.json",{"assets":entries})
    guarded_merge(map_folder/"manifest.json",entries)
    guarded_merge(ROOT/"godot_project/assets/generated/manifest.json",entries)
    # 대형 파일과 모든 캐시가 준비된 후 작은 지도 메타데이터 하나로 활성화한다.
    rollback = ROOT/"results/ulsan_80km_roads/map_meta_before.json"
    if not rollback.exists():
        rollback.write_bytes(meta_before)
    meta["assets"]["buildings_roads"] = uri+"buildings_and_roads.json"
    meta.pop("vector_source_meta",None)
    coverage = meta.setdefault("coverage",{})
    coverage["roads"] = {"coverage_complete":True,"revision":report["revision"],"extent_km":80,
                         "source_ways":report["source_ways"],"runtime_roads":report["runtime_roads"],
                         "collected_at":report["raw_collection"]["completed"].get("full_80km",{}).get("collected_at"),
                         "excluded_by_reason":report["excluded"],"attribution":"OpenStreetMap contributors, ODbL-1.0"}
    coverage["detailed_vectors_source"] = "건물: 기존 VWorld 자료 보존 / 도로: 80km 전체 OpenStreetMap"
    coverage["outer_buildings_collected"] = True
    coverage["outer_buildings_roads_collected"] = True
    meta["description_ko"] = "울산 중심 80km 지형과 기존 건물, 전 범위 OSM 간선·생활도로·보행로·임도 및 울산공항입니다."
    if meta_path.read_bytes()!=meta_before:
        raise RuntimeError("지도 설정 동시 변경으로 활성화를 보류합니다")
    save(meta_path,meta)
    meta_entry = {"file_path":"res://"+meta_path.relative_to(ROOT/"godot_project").as_posix(),
                  "sha256":digest(meta_path),"size_bytes":meta_path.stat().st_size,"bbox":meta["bbox"],
                  "elevation":{"min_meters":meta["min_elevation"],"max_meters":meta["max_elevation"]},"resolution":{"type":"map_configuration"}}
    for path in (map_folder/"manifest.json",ROOT/"godot_project/assets/generated/manifest.json"):
        guarded_merge(path,{"ulsan80_roads/active_map_meta":meta_entry})
    save(ROOT/"results/ulsan_80km_roads/published.json",{"revision":report["revision"],"active_uri":meta["assets"]["buildings_roads"],"rollback_meta":str(rollback.relative_to(ROOT))})
    print(f"활성화 완료: {meta['assets']['buildings_roads']}",flush=True)


def finalize():
    folder=ROOT/"godot_project/assets/maps/ulsan_metro_80km"
    path=folder/"map_meta.json"
    before=path.read_bytes()
    meta=json.loads(before)
    count=meta["simple_vector_map"]["counts"]["roads"]
    if count!=meta["coverage"]["roads"]["runtime_roads"]:
        raise RuntimeError("전술지도와 활성 도로 개수 불일치")
    meta["tactical_atlas"]["road_count"]=count
    meta["tactical_atlas"]["detail_note"]="80km 전체 OSM 도로 수집분. 생활도로·보행로는 얇은 선으로 표시한다."
    meta["description_en"]="80km terrain with preserved VWorld buildings, full-area OpenStreetMap roads and Ulsan airport."
    if path.read_bytes()!=before:
        raise RuntimeError("지도 메타데이터 동시 변경")
    save(path,meta)
    uri="res://"+path.relative_to(ROOT/"godot_project").as_posix()
    for manifest in (folder/"manifest.json",ROOT/"godot_project/assets/generated/manifest.json"):
        updates={key:{**entry,"sha256":digest(path),"size_bytes":path.stat().st_size}
                 for key,entry in read(manifest).get("assets",{}).items() if entry.get("file_path")==uri}
        guarded_merge(manifest,updates)
    vector_uri=meta["assets"]["buildings_roads"]
    verification=read(ROOT/"results/ulsan_80km_roads/verification.json")
    vector_folder=(ROOT/"godot_project"/vector_uri.removeprefix("res://")).parent
    for manifest in (folder/"manifest.json",ROOT/"godot_project/assets/generated/manifest.json",vector_folder/"manifest.json"):
        updates={key:{**entry,"resolution":{"type":"vector","buildings":verification["preserved_building_count"],"roads":count}}
                 for key,entry in read(manifest).get("assets",{}).items() if entry.get("file_path")==vector_uri}
        guarded_merge(manifest,updates)
    print(f"활성 전술지도 도로 {count}개",flush=True)


if __name__=="__main__":
    finalize() if "--finalize" in sys.argv else publish()
