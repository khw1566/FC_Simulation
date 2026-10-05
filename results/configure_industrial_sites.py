"""자동 후보 공단 생성 설정과 새 모듈 등록."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
path=root/"config/industrial_zones.json"
config=json.loads(path.read_text(encoding="utf-8"))
config.update(auto_candidates_enabled=True,candidate_size_m=1200,max_slope_degrees=8,max_road_grade=0.08,
              max_foundation_height_m=3.5,max_assets_per_zone=100,
              note_ko="울산 본항·온산항 주변의 로컬 안전 육지 후보에 생성하는 게임용 공단. 실제 공단 경계 및 공정 배치를 재현하지 않음.")
path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
for relative in ("module_index.json","godot_project/module_index.json"):
    path=root/relative
    before=path.read_bytes()
    doc=json.loads(before)
    modules=doc["domains"]["industrial_zones"]["modules"]
    for filename,responsibility in [("site_inputs.py","지형·수계·기존 시설 점유 형상과 배치 제외 영역"),
        ("road_graph.py","기존 도로에 연결되는 내부 도로 그래프"),("parcel_builder.py","도로 사이 배치 가능 필지 분할"),
        ("asset_placer.py","설비 전체 점유 형상과 진입 공간 검사"),("build_sites.py","안전 후보 선택과 공단 생성·매니페스트·검토 이미지 출력")]:
        module_path="pipeline/processors/industrial_zones/"+filename
        if not any(m["path"]==module_path for m in modules):
            modules.append({"path":module_path,"responsibility":responsibility})
    if path.read_bytes()!=before:
        raise RuntimeError("모듈 인덱스 동시 변경")
    path.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
