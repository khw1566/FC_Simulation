from pathlib import Path
import json
new=[('models','AtmosphereScatteringModel','godot_project/scripts/models/atmosphere_scattering_model.gd','광학용 지수 대기 밀도와 곡면 광학 경로 근사'),('services','AltitudeAtmosphereController','godot_project/scripts/services/altitude_atmosphere_controller.gd','카메라 고도에 따른 산란 셰이더와 원경 시야 갱신'),('terrain','HorizonHeightSampler','godot_project/scripts/terrain/horizon_height_sampler.gd','광역 축소 DEM의 지리 표본화 및 자료 범위 밖 외삽'),('terrain','HorizonRingBuilder','godot_project/scripts/terrain/horizon_ring_builder.gd','중앙을 비운 경량 원경 링과 경계 전이 생성'),('terrain','HorizonTerrainManager','godot_project/scripts/terrain/horizon_terrain_manager.gd','상세 지형 준비 이후 지도별 독립 원경 메시 생성'),('core','AtmosphereHorizonCheck','godot_project/scripts/core/atmosphere_horizon_check.gd','고도별 하늘과 원경 경량 검증'),('pipeline','HorizonTerrainBuilder','pipeline/processors/build_horizon_terrain.py','기존 DEM 축소 아틀라스와 해시 매니페스트 생성'),('shaders','AtmosphereScatteringShader','godot_project/shaders/atmosphere_scattering.gdshaderinc','레일리 위상함수와 곡면 대기 단일 산란 근사')]
for name in ['module_index.json','godot_project/module_index.json']:
 p=Path(name);d=json.loads(p.read_text(encoding='utf-8-sig'))
 for domain,cls,path,role in new:
  modules=d['domains'].setdefault(domain,{'description':'대기 및 원경 지원 계층','modules':[]})['modules']
  if not any(m.get('path')==path for m in modules):modules.append({'class_name':cls,'path':path,'responsibility':role})
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
