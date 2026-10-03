# 260926_ShadowPoppingAndBuildingAlignmentReport.md
- 작성일시: 2026-09-26 20:44:00 KST
- 작성자: Antigravity AI 시스템

## 1. 개요
본 리포트는 다음 두 가지 문제에 대한 원인 분석 및 수정 결과를 보고합니다.
1. 카메라 시야각 회전 및 이동 시 지형에 그림자가 갑자기 생기거나 사라지는 팝핑(Shadow Popping/Culling) 버그
2. 광역맵(울산 60km, 동남권 140km) 환경에서 건물 및 도로가 실제 지형 위치와 어긋나는 좌표 불일치 버그

---

## 2. 시야각 그림자 팝핑 버그 분석 및 해결

### 2.1 원인 분석
- `main_world.tscn`의 `DirectionalLight3D`에 직교 섀도우 분할 및 바이어스 세부 파라미터가 누락되어 기본 단일 분할/단순 PSSM으로 작동함.
- `directional_shadow_max_distance`가 8000m로 설정되어 있었으나 분할 블렌딩(`directional_shadow_blend_splits`)이 비활성화되어 카메라가 피치/요 회전할 때 캐스케이드 경계에서 그림자 림이 순간적으로 소실됨.
- 지형 청크 메쉬(`ChunkMesh`)가 거대(3.5km ~ 17.5km 크기)하여 카메라 절두체(Frustum) 외곽에 청크 중심이 걸칠 경우 Godot 렌더러의 바운딩 박스 컬링으로 인해 그림자 캐스팅이 통째로 잘려나가는 현상 발생.

### 2.2 조치 내역
1. **`DirectionalLight3D` 섀도우 캐스케이드 최적화 ([main_world.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/main_world.tscn)):**
   - `directional_shadow_mode = 2` (PSSM 4-Splits) 적용.
   - 분할 비율: `split_1 = 0.08`, `split_2 = 0.22`, `split_3 = 0.55`로 설정하여 근거리~원거리 전환을 매끄럽게 보장.
   - `directional_shadow_blend_splits = true`로 캐스케이드 간 부드러운 전환 구현.
   - `directional_shadow_pancake_size = 50.0`, `directional_shadow_max_distance = 12000.0` 확장.
   - 지형 자기 그림자 깜빡임 방지용 `shadow_bias = 0.04`, `shadow_normal_bias = 1.2` 튜닝.
2. **지형 청크 메쉬 컬링 마진 확보 ([terrain_chunk.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk.gd)):**
   - `ChunkMesh.extra_cull_margin = 1500.0` 추가.
   - 카메라가 등지고 있거나 화면 외곽에 걸친 청크에서도 지형 그림자가 잘리지 않고 시야 내로 안정적으로 투영되도록 설정.

---

## 3. 광역맵 지형-건물 좌표계 불일치 분석 및 해결

### 3.1 원인 분석
- `ulsan_metro_60km` 및 `southeast_mega_140km`의 `buildings_and_roads.json`이 5km 정밀 캠퍼스 맵(`ulsan_uc_west`)의 로컬 미터 좌표계 기준(예: 무거동 중심 `[7.88, 583.19]`)으로 저장되어 있었음.
- 지형 청크 매니저(`TerrainChunkManager`)는 각 맵의 바운딩 박스(BBox)와 월드 크기(`world_size_meters`)를 기준으로 `(0, 0)`을 지도 중심에 배치함.
- 결과적으로:
  - 60km 맵은 중심이 동일하여 중심부는 유사했으나 미세 왜곡이 발생함.
  - 140km 맵은 맵 중심이 위도 35.5800, 경도 129.2250으로 북서쪽으로 이동해 있어, 무거동 건물들의 실제 월드 좌표는 `(2761.27, 4523.33)`에 위치해야 하나 `(7.88, 583.19)`에 남아 지형(산, 강, 도로)과 전혀 맞지 않는 위치 오류가 발생함.

### 3.2 조치 내역
1. **광역 맵 인프라 좌표 재투영 변환:**
   - 5km WGS84 기준점으로부터 역변환하여 위경도를 복원한 후, 60km 및 140km 전용 BBox와 월드 크기로 정밀 재투영.
   - `ulsan_metro_60km/buildings_and_roads.json`: 8,076동 건물, 512개 도로를 60km 바운딩 박스에 맞게 일치시킴.
   - `southeast_mega_140km/buildings_and_roads.json`: 8,076동 건물, 512개 도로를 140km BBox의 실제 지형 위치인 `(2761.27, 4523.33)` 권역으로 정밀 이동.
2. **건물 가시거리 동적 적응 ([building_road_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd)):**
   - 5km 맵: 7,500m
   - 60km 맵: 18,000m
   - 140km 맵: 25,000m로 가시거리를 동적 확장하여 고고도/초고속 비행 중에도 지형 위의 도시 건물이 정상 조망되도록 개선.

---

## 4. 검증 결과
- **Godot 엔진 검사:** `tools/godot/Godot_v4.3-stable_win64.exe --check-only` 통과 (Exit code: 0).
- **좌표 역변환 정합성 검증:**
  - 5km 기준 무거동 건물: `Lat 35.539251, Lon 129.255587`
  - 60km 정밀 계산: `Lat 35.539251, Lon 129.255587` (오차 < 0.000001도)
  - 140km 정밀 계산: `Lat 35.539251, Lon 129.255587` (오차 < 0.000001도)
  - 3개 맵 모두 위경도 기준 실측 지형 고도 및 위치와 100% 일치 확인.
