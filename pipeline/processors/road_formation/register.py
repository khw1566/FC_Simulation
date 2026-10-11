"""도로 노반·거리 표시 정책과 전용 생성·확인 도구를 모듈 색인에 병합한다."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def register():
    runtime = ["road_formation_grader.gd","road_formation_field.gd","road_earthwork_mesher.gd",
               "road_visibility_policy.gd","terrain_chunk_manager.gd","terrain_chunk.gd","terrain_chunk_mesher.gd",
               "road_batch_builder.gd","road_mesh_builder.gd","road_terrain_tessellator.gd","building_road_manager.gd"]
    paths = [ROOT/"godot_project/scripts/terrain"/name for name in runtime]
    paths += [ROOT/"godot_project/shaders/road_surface.gdshader"]
    tools = sorted(Path(__file__).parent.glob("*.py"))+sorted(Path(__file__).parent.glob("*.gd"))
    modules = [{"path":p.relative_to(ROOT).as_posix(),"lines":len(p.read_text(encoding="utf-8").splitlines())}
               for p in paths+tools]
    assert all(m["lines"]<600 for m in modules)
    local = {"description":"원본 보존 도로 노반 선분 생성과 독립 경사면·밀집 구역 검증","modules":modules[len(paths):]}
    (Path(__file__).parent/"module_index.json").write_text(json.dumps(local,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for path in (ROOT/"module_index.json",ROOT/"godot_project/module_index.json"):
        before = path.read_bytes()
        doc = json.loads(before)
        for domain in doc["domains"].values():
            for entry in domain.get("modules",[]):
                if isinstance(entry,dict):
                    match = next((m for m in modules if m["path"]==entry.get("path")),None)
                    if match:
                        entry["lines"] = match["lines"]
        doc["domains"]["road_formation"] = {"description":"도로 횡단 노반 절토·성토와 폭별 공간 배치·거리 컬링","modules":modules}
        if path.read_bytes()!=before:
            raise RuntimeError("모듈 색인 동시 변경")
        temp = path.with_suffix(".road_formation.tmp")
        temp.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        if path.read_bytes()!=before:
            temp.unlink()
            raise RuntimeError("모듈 색인 동시 변경")
        temp.replace(path)
    print(f"도로 노반 모듈 {len(modules)}개 등록")


if __name__=="__main__":
    register()
