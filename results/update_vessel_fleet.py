"""선박 증편 설정 및 항적 모듈 색인 갱신."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config_path = root / "config/vessel_traffic.json"
config = json.loads(config_path.read_text(encoding="utf-8"))
config.update(sailing_copies_per_type=3, moored_copies_per_type=2,
              wake_enabled=True, wake_max_lifetime_seconds=65)
config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
for name in ("module_index.json", "godot_project/module_index.json"):
    path = root / name
    doc = json.loads(path.read_text(encoding="utf-8-sig"))
    modules = doc["domains"]["water"]["modules"]
    if not any(m.get("class_name") == "VesselWake" for m in modules):
        modules.append({"class_name":"VesselWake", "path":"godot_project/scripts/water/vessel_wake.gd",
                        "responsibility":"선체 크기와 운항 속도에 따른 세계 좌표 거품 항적의 생성·확산·소멸",
                        "key_methods":["configure()", "advance()"]})
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
