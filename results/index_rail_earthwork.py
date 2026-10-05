"""철도 국소 지형 보정 모듈 색인."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for relative in ("module_index.json", "godot_project/module_index.json"):
    path = root / relative
    original = path.read_bytes()
    doc = json.loads(original)
    modules = doc["domains"]["terrain"]["modules"]
    if not any(m.get("class_name") == "RailwayTerrainGrader" for m in modules):
        modules.append({"class_name":"RailwayTerrainGrader",
                        "path":"godot_project/scripts/terrain/railway_terrain_grader.gd",
                        "responsibility":"LOD 지형의 철로 주변 삼각형 국소 세분화 및 연속 절토, 동일 높이 조회",
                        "key_methods":["configure()", "cells()", "corrected_height()", "add_triangle()"]})
    if path.read_bytes() != original:
        raise RuntimeError("모듈 인덱스 동시 변경: 재실행 필요")
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
