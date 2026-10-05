# 전체 에셋 인덱스
수동 갱신 결과. 상세 경로·SHA256·원본 매니페스트 메타데이터는 `asset_index.json`을 참조한다.

총 23,226개 파일. 쓰기 중 보류 0개. 지도 리비전은 보존된 자료이며 활성 여부를 추정하지 않는다.

| 분류 | 파일 수 | 구성 |
|---|---:|---|
| 공항 (airport) | 2 | 데이터·메타데이터 1, 씬 1 |
| 공통 에셋 메타데이터 (asset_metadata) | 2 | 데이터·메타데이터 2 |
| 교량 (bridges) | 8 | 씬 8 |
| 문화유산 (heritage) | 3 | 씬 2, 데이터·메타데이터 1 |
| 원경 (horizon) | 5 | 데이터·메타데이터 2, 문서 1, 고도 래스터 1, 이미지 1 |
| 산업·공단 (industrial) | 36 | 데이터·메타데이터 2, 모델 16, 씬 16, 이미지 1, 문서 1 |
| 공단 야간 조명 (industrial_lighting) | 31 | 데이터·메타데이터 2, 씬 28, 문서 1 |
| 플랜트 탑·배관·연기 (industrial_plant) | 32 | 데이터·메타데이터 2, 모델 12, 씬 16, 이미지 1, 문서 1 |
| 공단 구역 마스크 (industrial_zones) | 11 | 이미지 5, 데이터·메타데이터 5, 문서 1 |
| 일본 공항 (japan_airports) | 19 | 씬 18, 데이터·메타데이터 1 |
| 지도 (maps) | 22,929 | 데이터·메타데이터 17876, 이미지 242, 벡터 이미지 4808, 지리 데이터 3 |
| 보행교 (pedestrian_bridges) | 10 | 이미지 4, 씬 3, 데이터·메타데이터 2, 문서 1 |
| 철도 (railway) | 16 | 데이터·메타데이터 7, 이미지 2, 씬 6, 문서 1 |
| 철도교 (railway_bridges) | 24 | 씬 10, 이미지 11, 데이터·메타데이터 2, 문서 1 |
| 철도터널 (railway_tunnels) | 13 | 데이터·메타데이터 2, 씬 10, 문서 1 |
| 셰이더 (shaders) | 16 | 셰이더 16 |
| 역사·역세권 (taehwagang) | 14 | 모델 5, 씬 5, 이미지 2, 데이터·메타데이터 1, 문서 1 |
| 지형·지도 기반 (terrain) | 11 | 벡터 이미지 2, 데이터·메타데이터 5, 이미지 4 |
| 지형 타일 (tiles) | 17 | 이미지 16, 데이터·메타데이터 1 |
| UI (ui) | 6 | 이미지 3, 벡터 이미지 3 |
| 선박 (vessels) | 16 | 모델 6, 씬 6, 이미지 1, 데이터·메타데이터 2, 문서 1 |
| 발전소 (wolsong) | 5 | 데이터·메타데이터 1, 이미지 1, 문서 1, 모델 1, 씬 1 |

## 모델 및 씬 목록
같은 이름의 GLB와 씬은 같은 에셋의 표현 파일이며 별도 모델 종류로 중복 계산하지 않는다.

### 공항
- `godot_project/assets/generated/airport/ulsan_airport.scn`
### 교량
- `godot_project/assets/generated/bridges/bridge_00.scn`
- `godot_project/assets/generated/bridges/bridge_01.scn`
- `godot_project/assets/generated/bridges/bridge_02.scn`
- `godot_project/assets/generated/bridges/bridge_03.scn`
- `godot_project/assets/generated/bridges/bridge_04.scn`
- `godot_project/assets/generated/bridges/bridge_05.scn`
- `godot_project/assets/generated/bridges/bridge_06.scn`
- `godot_project/assets/generated/bridges/bridge_07.scn`
### 문화유산
- `godot_project/assets/generated/heritage/eonyang_eupseong.scn`
- `godot_project/assets/generated/heritage/ulsan_waeseong.scn`
### 산업·공단
- 냉각 팬 설비 — `godot_project/assets/generated/industrial/cooling_fan_bank.glb`
- 냉각 팬 설비 — `godot_project/assets/generated/industrial/cooling_fan_bank.tscn`
- 냉각탑 — `godot_project/assets/generated/industrial/cooling_tower.glb`
- 냉각탑 — `godot_project/assets/generated/industrial/cooling_tower.tscn`
- 증류탑 — `godot_project/assets/generated/industrial/distillation_tower.glb`
- 증류탑 — `godot_project/assets/generated/industrial/distillation_tower.tscn`
- 평지붕 공장 — `godot_project/assets/generated/industrial/factory_flat.glb`
- 평지붕 공장 — `godot_project/assets/generated/industrial/factory_flat.tscn`
- 박공지붕 공장 — `godot_project/assets/generated/industrial/factory_gable.glb`
- 박공지붕 공장 — `godot_project/assets/generated/industrial/factory_gable.tscn`
- 톱니지붕 공장 — `godot_project/assets/generated/industrial/factory_sawtooth.glb`
- 톱니지붕 공장 — `godot_project/assets/generated/industrial/factory_sawtooth.tscn`
- 갠트리 크레인 — `godot_project/assets/generated/industrial/gantry_crane.glb`
- 갠트리 크레인 — `godot_project/assets/generated/industrial/gantry_crane.tscn`
- 대형 연통 — `godot_project/assets/generated/industrial/industrial_chimney.glb`
- 대형 연통 — `godot_project/assets/generated/industrial/industrial_chimney.tscn`
- 원통형 액체저장고 — `godot_project/assets/generated/industrial/liquid_storage_tank.glb`
- 원통형 액체저장고 — `godot_project/assets/generated/industrial/liquid_storage_tank.tscn`
- 구형 LPG저장고 — `godot_project/assets/generated/industrial/lpg_sphere.glb`
- 구형 LPG저장고 — `godot_project/assets/generated/industrial/lpg_sphere.tscn`
- 파이프라인 곡관 — `godot_project/assets/generated/industrial/pipeline_elbow.glb`
- 파이프라인 곡관 — `godot_project/assets/generated/industrial/pipeline_elbow.tscn`
- 파이프라인 직선 — `godot_project/assets/generated/industrial/pipeline_straight.glb`
- 파이프라인 직선 — `godot_project/assets/generated/industrial/pipeline_straight.tscn`
- 파이프라인 분기 — `godot_project/assets/generated/industrial/pipeline_tee.glb`
- 파이프라인 분기 — `godot_project/assets/generated/industrial/pipeline_tee.tscn`
- 조선용 대형 격납고 — `godot_project/assets/generated/industrial/shipbuilding_hangar.glb`
- 조선용 대형 격납고 — `godot_project/assets/generated/industrial/shipbuilding_hangar.tscn`
- 타워 크레인 — `godot_project/assets/generated/industrial/tower_crane.glb`
- 타워 크레인 — `godot_project/assets/generated/industrial/tower_crane.tscn`
- 송전탑 — `godot_project/assets/generated/industrial/transmission_tower.glb`
- 송전탑 — `godot_project/assets/generated/industrial/transmission_tower.tscn`
### 공단 야간 조명
- `godot_project/assets/generated/industrial_lighting/industrial--cooling_fan_bank.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--cooling_tower.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--distillation_tower.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--factory_flat.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--factory_gable.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--factory_sawtooth.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--gantry_crane.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--industrial_chimney.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--liquid_storage_tank.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--lpg_sphere.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--pipeline_elbow.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--pipeline_straight.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--pipeline_tee.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--shipbuilding_hangar.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--tower_crane.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial--transmission_tower.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--flare_lattice.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--process_column.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--rack_cross.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--rack_double.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--rack_elbow.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--rack_riser.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--rack_straight.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--rack_tee.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--scrubber_tower.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--stack_concrete.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--stack_steel.tscn`
- `godot_project/assets/generated/industrial_lighting/industrial_plant--stack_triple.tscn`
### 플랜트 탑·배관·연기
- 격자 지지 플레어 탑 — `godot_project/assets/generated/industrial_plant/flare_lattice.glb`
- 격자 지지 플레어 탑 — `godot_project/assets/generated/industrial_plant/flare_lattice.tscn`
- `godot_project/assets/generated/industrial_plant/plant_assembly_demo.tscn`
- 다단 정유 공정 탑 — `godot_project/assets/generated/industrial_plant/process_column.glb`
- 다단 정유 공정 탑 — `godot_project/assets/generated/industrial_plant/process_column.tscn`
- 배관 랙 교차 — `godot_project/assets/generated/industrial_plant/rack_cross.glb`
- 배관 랙 교차 — `godot_project/assets/generated/industrial_plant/rack_cross.tscn`
- 배관 랙 2층 — `godot_project/assets/generated/industrial_plant/rack_double.glb`
- 배관 랙 2층 — `godot_project/assets/generated/industrial_plant/rack_double.tscn`
- 배관 랙 곡관 — `godot_project/assets/generated/industrial_plant/rack_elbow.glb`
- 배관 랙 곡관 — `godot_project/assets/generated/industrial_plant/rack_elbow.tscn`
- 배관 랙 높이 전환 — `godot_project/assets/generated/industrial_plant/rack_riser.glb`
- 배관 랙 높이 전환 — `godot_project/assets/generated/industrial_plant/rack_riser.tscn`
- 배관 랙 직선 — `godot_project/assets/generated/industrial_plant/rack_straight.glb`
- 배관 랙 직선 — `godot_project/assets/generated/industrial_plant/rack_straight.tscn`
- 배관 랙 분기 — `godot_project/assets/generated/industrial_plant/rack_tee.glb`
- 배관 랙 분기 — `godot_project/assets/generated/industrial_plant/rack_tee.tscn`
- 습식 세정·배기 탑 — `godot_project/assets/generated/industrial_plant/scrubber_tower.glb`
- 습식 세정·배기 탑 — `godot_project/assets/generated/industrial_plant/scrubber_tower.tscn`
- `godot_project/assets/generated/industrial_plant/smoke_dark.tscn`
- `godot_project/assets/generated/industrial_plant/smoke_gray.tscn`
- 고층 표식 연통 — `godot_project/assets/generated/industrial_plant/stack_concrete.glb`
- 고층 표식 연통 — `godot_project/assets/generated/industrial_plant/stack_concrete.tscn`
- 슬림 강철 연통 — `godot_project/assets/generated/industrial_plant/stack_steel.glb`
- 슬림 강철 연통 — `godot_project/assets/generated/industrial_plant/stack_steel.tscn`
- 3구 집합 연통 — `godot_project/assets/generated/industrial_plant/stack_triple.glb`
- 3구 집합 연통 — `godot_project/assets/generated/industrial_plant/stack_triple.tscn`
- `godot_project/assets/generated/industrial_plant/steam_white.tscn`
### 일본 공항
- `godot_project/assets/generated/japan_airports/JP-0007.scn`
- `godot_project/assets/generated/japan_airports/RJDA.scn`
- `godot_project/assets/generated/japan_airports/RJDB.scn`
- `godot_project/assets/generated/japan_airports/RJDC.scn`
- `godot_project/assets/generated/japan_airports/RJFA.scn`
- `godot_project/assets/generated/japan_airports/RJFF.scn`
- `godot_project/assets/generated/japan_airports/RJFK.scn`
- `godot_project/assets/generated/japan_airports/RJFM.scn`
- `godot_project/assets/generated/japan_airports/RJFN.scn`
- `godot_project/assets/generated/japan_airports/RJFO.scn`
- `godot_project/assets/generated/japan_airports/RJFR.scn`
- `godot_project/assets/generated/japan_airports/RJFS.scn`
- `godot_project/assets/generated/japan_airports/RJFT.scn`
- `godot_project/assets/generated/japan_airports/RJFU.scn`
- `godot_project/assets/generated/japan_airports/RJFY.scn`
- `godot_project/assets/generated/japan_airports/RJFZ.scn`
- `godot_project/assets/generated/japan_airports/RJOF.scn`
- `godot_project/assets/generated/japan_airports/RJOZ.scn`
### 보행교
- 범용 보행 육교 — `godot_project/assets/generated/pedestrian_bridges/generic_pedestrian_overpass.scn`
- 굴화리–다운동 도보 징검다리 — `godot_project/assets/generated/pedestrian_bridges/gulhwa_daun_crossing.scn`
- 선바위교 — `godot_project/assets/generated/pedestrian_bridges/seonbawi_bridge.scn`
### 철도
- 동해선 광역전철 야간 조명 조립 예제 — `godot_project/assets/generated/railway/night_assets/donghae_night_scene.scn`
- 동해선 광역전철 야간 식별 철로 — `godot_project/assets/generated/railway/night_assets/donghae_track.scn`
- 동해선 광역전철 야간 조명 열차 — `godot_project/assets/generated/railway/night_assets/donghae_train.scn`
- 경부고속선 KTX 야간 조명 조립 예제 — `godot_project/assets/generated/railway/night_assets/ktx_night_scene.scn`
- 경부고속선 KTX 야간 식별 철로 — `godot_project/assets/generated/railway/night_assets/ktx_track.scn`
- 경부고속선 KTX 야간 조명 열차 — `godot_project/assets/generated/railway/night_assets/ktx_train.scn`
### 철도교
- 안양교 병렬 상로 아치 본체 — `godot_project/assets/generated/railway_bridges/anyang_main_bridge.scn`
- 안양교 북측 접근 고가교 — `godot_project/assets/generated/railway_bridges/anyang_north_approach.scn`
- 울산역 방향 접근 고가교 — `godot_project/assets/generated/railway_bridges/anyang_station_approach.scn`
- 복선 콘크리트 박스거더교 — `godot_project/assets/generated/railway_bridges/rail_box_girder.scn`
- 복선 상로 아치교 — `godot_project/assets/generated/railway_bridges/rail_deck_arch.scn`
- 복선 다경간 고가교 — `godot_project/assets/generated/railway_bridges/rail_multi_viaduct.scn`
- 단선 강판거더교 — `godot_project/assets/generated/railway_bridges/rail_plate_girder.scn`
- 복선 강재 트러스교 — `godot_project/assets/generated/railway_bridges/rail_through_truss.scn`
- 안양교–울산역 연결 세트 — `godot_project/assets/generated/railway_bridges/ulsan_anyang_connected_set.scn`
- 울산역 연결부 — `godot_project/assets/generated/railway_bridges/ulsan_station_interface.scn`
### 철도터널
- 동해선용 복선 터널 반복 내부 구간 — `godot_project/assets/generated/railway_tunnels/donghae_tunnel_body.scn`
- 동해선용 복선 터널 입구 — `godot_project/assets/generated/railway_tunnels/donghae_tunnel_entry.scn`
- 동해선용 복선 터널 출구 — `godot_project/assets/generated/railway_tunnels/donghae_tunnel_exit.scn`
- 동해선용 복선 터널 내부 구조 확인용 — `godot_project/assets/generated/railway_tunnels/donghae_tunnel_inspection.scn`
- 동해선용 복선 터널 연결 세트 — `godot_project/assets/generated/railway_tunnels/donghae_tunnel_set.scn`
- 고속철도용 복선 터널 반복 내부 구간 — `godot_project/assets/generated/railway_tunnels/hsr_tunnel_body.scn`
- 고속철도용 복선 터널 입구 — `godot_project/assets/generated/railway_tunnels/hsr_tunnel_entry.scn`
- 고속철도용 복선 터널 출구 — `godot_project/assets/generated/railway_tunnels/hsr_tunnel_exit.scn`
- 고속철도용 복선 터널 내부 구조 확인용 — `godot_project/assets/generated/railway_tunnels/hsr_tunnel_inspection.scn`
- 고속철도용 복선 터널 연결 세트 — `godot_project/assets/generated/railway_tunnels/hsr_tunnel_set.scn`
### 역사·역세권
- `godot_project/assets/generated/taehwagang/district.glb`
- `godot_project/assets/generated/taehwagang/district.tscn`
- `godot_project/assets/generated/taehwagang/forecourt.glb`
- `godot_project/assets/generated/taehwagang/forecourt.tscn`
- `godot_project/assets/generated/taehwagang/rail_yard.glb`
- `godot_project/assets/generated/taehwagang/rail_yard.tscn`
- `godot_project/assets/generated/taehwagang/station.glb`
- `godot_project/assets/generated/taehwagang/station.tscn`
- `godot_project/assets/generated/taehwagang/taehwagang_complete.glb`
- `godot_project/assets/generated/taehwagang/taehwagang_complete.tscn`
### 선박
- 컨테이너선 — `godot_project/assets/generated/vessels/container_ship.glb`
- `godot_project/assets/generated/vessels/container_ship.tscn`
- 어업용 소형선박 — `godot_project/assets/generated/vessels/fishing_boat.glb`
- `godot_project/assets/generated/vessels/fishing_boat.tscn`
- LPG선 — `godot_project/assets/generated/vessels/lpg_carrier.glb`
- `godot_project/assets/generated/vessels/lpg_carrier.tscn`
- 보트 — `godot_project/assets/generated/vessels/motor_boat.glb`
- `godot_project/assets/generated/vessels/motor_boat.tscn`
- 유조선 — `godot_project/assets/generated/vessels/oil_tanker.glb`
- `godot_project/assets/generated/vessels/oil_tanker.tscn`
- 예인선 — `godot_project/assets/generated/vessels/tugboat.glb`
- `godot_project/assets/generated/vessels/tugboat.tscn`
### 발전소
- `godot_project/assets/generated/wolsong/wolsong_npp.glb`
- `godot_project/assets/generated/wolsong/wolsong_npp.tscn`
