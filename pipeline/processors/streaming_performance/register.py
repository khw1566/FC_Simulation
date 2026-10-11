"""스트리밍 개선 모듈을 기존 색인을 보존하며 병합한다."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def register():
    names = ["stream_frame_budget.gd","terrain_upload_pages.gd","terrain_mesh_upload.gd",
             "terrain_chunk.gd","terrain_chunk_mesher.gd","terrain_chunk_manager.gd",
             "road_earthwork_detail.gd","road_earthwork_mesher.gd","road_formation_grader.gd",
             "road_batch_builder.gd","building_road_manager.gd","building_mesh_builder.gd",
             "building_batch_assembler.gd","building_collision_stream.gd","vector_data_stream.gd"]
    runtime = [ROOT/"godot_project/scripts/terrain"/name for name in names]
    runtime += [ROOT/"godot_project/scripts/views/performance_hud.gd",ROOT/"godot_project/scripts/testing/prebaked_rail_baker.gd"]
    package = Path(__file__).parent
    scripts = sorted(package.glob("*.py"))+sorted(package.glob("*.gd"))
    entries = [{"path":p.relative_to(ROOT).as_posix(),"lines":len(p.read_text(encoding="utf-8").splitlines())} for p in runtime+scripts]
    assert all(entry["lines"]<600 for entry in entries)
    local = {"description":"분리 스트리밍 측정과 LOD·건물·충돌 검증","modules":entries[len(runtime):]}
    (package/"module_index.json").write_text(json.dumps(local,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for path in (ROOT/"module_index.json",ROOT/"godot_project/module_index.json"):
        original = path.read_bytes()
        doc = json.loads(original)
        by_path = {entry["path"]:entry["lines"] for entry in entries}
        for domain in doc["domains"].values():
            for entry in domain.get("modules",[]):
                if isinstance(entry,dict) and entry.get("path") in by_path:
                    entry["lines"] = by_path[entry["path"]]
        doc["domains"]["streaming_performance"] = {"description":"공유 프레임 예산과 지형 페이지 업로드·이동 구역 끊김 개선","modules":entries}
        temp = path.with_suffix(".streaming_performance.tmp")
        temp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        if path.read_bytes()!=original:
            temp.unlink()
            raise RuntimeError("모듈 색인 동시 변경: 재시도 필요")
        temp.replace(path)
    print(f"스트리밍 모듈 {len(entries)}개 등록, 최대 {max(e['lines'] for e in entries)}줄")


if __name__=="__main__":
    register()
