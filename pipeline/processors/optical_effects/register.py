"""광학 효과·건물 그림자 정책과 독립 확인 도구를 기존 모듈 색인에 병합한다."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def register():
    runtime = ["scripts/weather/optical_effects_controller.gd", "scripts/weather/cloud_layer_factory.gd",
               "scripts/weather/procedural_cloud_manager.gd", "scripts/terrain/building_shadow_policy.gd",
               "scripts/terrain/building_mesh_builder.gd", "shaders/sky_cloud_layer.gdshader"]
    paths = [ROOT / "godot_project" / p for p in runtime]
    paths += sorted((ROOT / "godot_project/shaders/optics").glob("*.gdshader*"))
    tools = sorted(Path(__file__).parent.glob("*.py")) + sorted(Path(__file__).parent.glob("*.gd"))
    modules = [{"path": p.relative_to(ROOT).as_posix(), "lines": len(p.read_text(encoding="utf-8").splitlines())}
               for p in paths + tools]
    assert all(m["lines"] < 600 for m in modules)
    local = {"description": "광학 효과의 격리 렌더링·설정·가림·기하 보존 확인", "modules": modules[len(paths):]}
    (Path(__file__).parent / "module_index.json").write_text(json.dumps(local, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for path in (ROOT / "module_index.json", ROOT / "godot_project/module_index.json"):
        before = path.read_bytes()
        doc = json.loads(before)
        for domain in doc["domains"].values():
            for entry in domain.get("modules", []):
                if isinstance(entry, dict):
                    match = next((m for m in modules if m["path"] == entry.get("path")), None)
                    if match:
                        entry["lines"] = match["lines"]
        doc["domains"]["optical_effects"] = {"description": "공유 구름 밀도 기반 지면 그림자·안개 광선·깊이 가림 플레어와 소형 밀집 건물 그림자 제외", "modules": modules}
        if path.read_bytes() != before:
            raise RuntimeError("모듈 색인 동시 변경")
        temp = path.with_suffix(".optics.tmp")
        temp.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if path.read_bytes() != before:
            temp.unlink()
            raise RuntimeError("모듈 색인 동시 변경")
        temp.replace(path)
    print(f"광학 모듈 {len(modules)}개 등록")


if __name__ == "__main__":
    register()
