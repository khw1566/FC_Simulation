"""공단 월드 실행 모듈 색인."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
for relative in ("module_index.json","godot_project/module_index.json"):
    path=root/relative
    before=path.read_bytes()
    doc=json.loads(before)
    modules=doc["domains"]["industrial_zones"]["modules"]
    for name,responsibility in [("industrial_asset_factory","원본 GLB 공유 캐시와 포트 배관 랙·조명·연기 조립"),
        ("industrial_placement_builder","현재 지형 LOD에 맞춘 설비 위치와 지표 연결 기초"),
        ("industrial_road_builder","기존 도로 지형 밀착 방식의 공단 도로와 진입로"),
        ("industrial_zone_manager","공단 로드·청크 거리 표시·상세 모델 생성 예산과 설정 토글")]:
        module_path="godot_project/scripts/terrain/"+name+".gd"
        if not any(m["path"]==module_path for m in modules):
            modules.append({"path":module_path,"responsibility":responsibility})
    if path.read_bytes()!=before:
        raise RuntimeError("모듈 인덱스 동시 변경")
    path.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
