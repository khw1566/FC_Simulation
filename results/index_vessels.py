from pathlib import Path
import json
new=[('water','VesselRoute','godot_project/scripts/water/vessel_route.gd','정박과 해상 왕복 운항의 위치 및 방향 샘플링'),('water','VesselModelFactory','godot_project/scripts/water/vessel_model_factory.gd','원본 선박 GLB 수면 기준 및 크기를 보존한 공유 모델 로드'),('water','VesselWorldManager','godot_project/scripts/water/vessel_world_manager.gd','지도별 선박 배치와 거리 표시 및 설정 활성화'),('core','VesselTrafficCheck','godot_project/scripts/core/vessel_traffic_check.gd','전체 맵 없는 선박 운항, UI, 설정 저장 검증'),('vessels','VesselNavigationGrid','pipeline/processors/vessels/navigation_grid.py','선체 여유를 확보한 해수 격자 탐색'),('vessels','VesselTrafficBuilder','pipeline/processors/vessels/build_traffic.py','지도별 항포구 항로 생성과 해시 매니페스트 갱신')]
for name in ['module_index.json','godot_project/module_index.json']:
 p=Path(name);d=json.loads(p.read_text(encoding='utf-8-sig'))
 for domain,cls,path,role in new:
  modules=d['domains'].setdefault(domain,{'description':'선박 운항 지원 계층','modules':[]})['modules']
  if not any(m.get('path')==path for m in modules):modules.append({'class_name':cls,'path':path,'responsibility':role})
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
