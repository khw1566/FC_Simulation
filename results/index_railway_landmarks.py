from pathlib import Path
import json
new=[('terrain','RailwayLandmarkManager','godot_project/scripts/terrain/railway_landmark_manager.gd','태화강역 역사, 안양교 및 주변 범용 교량 배치와 중복 역사 제거'),('terrain','RailwayAssetPathFitter','godot_project/scripts/terrain/railway_asset_path_fitter.gd','원본 철로 교량을 실제 철도 선형 및 지면 높이에 맞춰 복제 변형'),('pipeline','RailwayLandmarkPlacementBuilder','pipeline/processors/build_railway_landmark_placements.py','원본 OSM 역사 윤곽과 철도에서 배치 목록 및 해시 인덱스 생성')]
for name in ['module_index.json','godot_project/module_index.json']:
 p=Path(name);d=json.loads(p.read_text(encoding='utf-8-sig'))
 for domain,cls,path,role in new:
  modules=d['domains'].setdefault(domain,{'description':'철도 랜드마크 계층','modules':[]})['modules']
  if not any(m.get('path')==path for m in modules):modules.append({'class_name':cls,'path':path,'responsibility':role})
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
