"""공단 마스킹 기초 모듈 등록."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for relative in ("module_index.json", "godot_project/module_index.json"):
    path = root / relative
    original = path.read_bytes()
    doc = json.loads(original)
    doc["domains"]["industrial_zones"] = {
        "description":"공단 경계 수동 지정과 절차 생성용 기초 마스킹",
        "modules":[
            {"class_name":"IndustrialZoneMaskBuilder", "path":"pipeline/processors/industrial_zones/build_masks.py", "responsibility":"사용자 GeoJSON의 구역 ID·수계 제외·1차 허용 마스크 생성"},
            {"path":"pipeline/processors/industrial_zones/__init__.py", "responsibility":"공단 구역 처리 패키지"},
            {"path":"previews/industrial_zone_editor/editor.html", "responsibility":"지도 위 공단 외곽 지정과 GeoJSON 수동 입출력"}
        ]}
    if path.read_bytes() != original:
        raise RuntimeError("모듈 인덱스 동시 변경: 재실행 필요")
    path.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n", encoding="utf-8")
