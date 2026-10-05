from pathlib import Path
import json
new=[('terrain','RailwayAlignmentCatalog','godot_project/scripts/terrain/railway_alignment_catalog.gd','공유 절점의 연속 종단과 터널 배치 목록 로드'),('terrain','RailwayTunnelWorldManager','godot_project/scripts/terrain/railway_tunnel_world_manager.gd','노선별 터널 입구·내부·출구의 거리 기반 생성 및 해제'),('terrain','RailwayTerrainVoid','godot_project/scripts/terrain/railway_terrain_void.gd','터널 통로의 지형 표시 및 충돌 제거와 탐색 바닥 높이'),('pipeline','RailwayAlignmentBuilder','pipeline/processors/build_railway_alignment.py','철도 종단 평활화, 경사 포락선, 절성토 높이맵 및 터널 공간 마스크 생성')]
for name in ['module_index.json','godot_project/module_index.json']:
 p=Path(name);d=json.loads(p.read_text(encoding='utf-8-sig'))
 for domain,cls,path,role in new:
  modules=d['domains'].setdefault(domain,{'description':'철도 종단 및 터널 계층','modules':[]})['modules']
  if not any(m.get('path')==path for m in modules):modules.append({'class_name':cls,'path':path,'responsibility':role})
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
