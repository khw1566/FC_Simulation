# 260923_CoastlineAndRiverFixReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 하천 및 해양 영역에서 발생하던 건물 오인식 중복 결함과 해안선 픽셀 계단 현상 및 인위적 선형 오브젝트를 제거하고 자연스러운 해안 지형으로 정밀 조작한 작업 결과를 기록합니다.

## 2. 결함 원인 분석
- **강/하천 위 건물 중복 생성 결함:**
  - 딥러닝 피복 분류 모델 및 OSM 풋프린트 추출기에서 수계 마스크와의 교차 검증이 부재하여 해양 및 하천 수면(표고 0.2m 이하 및 수계 마스크 영역) 상에 건물이 생성됨.
  - 지형 셰이더([procedural_terrain.gdshader](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/shaders/procedural_terrain.gdshader))에서 `splat.b`(도회지/인공구조물 텍스처) 샘플링 시 수계 마스크 차단 조건이 없어 하천 구간에 회색 도회지 텍스처가 겹쳐서 출력됨.
- **해안선 사각형 픽셀 계단 및 인위적 선형 오브젝트 결함:**
  - [CoastlineWaterwayManager](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/water/coastline_waterway_manager.gd)에서 8m 폭의 해안선 쇄파대 리본 메쉬를 강제로 덮어씌워 인위적인 선으로 표현됨.
  - 고도 데이터(DEM) 원본의 낮은 서브픽셀 해상도로 인해 해수면 접점 경계가 사각형 계단 형태로 나타남.

## 3. 조치 및 개선 사항
- **해안선 별도 오브젝트 제거:**
  - [CoastlineWaterwayManager](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/water/coastline_waterway_manager.gd)의 `_render_coastlines_batched` 호출을 비활성화하여 인위적인 리본 메쉬를 완전히 배제함.
- **높이맵 해안선 서브픽셀 스무딩 알고리즘 구현:**
  - [HeightmapProcessor](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/heightmap_processor.py)에 `_smooth_natural_coastline` 메서드를 추가함.
  - 해수면 완충대(-1.0m ~ 3.5m) 및 OSM 실측 해안선 벡터 주변에 양방향 거리 변환(Distance Transform)과 다중 스케일 가우시안 안티에일리어싱을 적용하여 사각형 픽셀 계단을 완전히 제거하고 유려한 자연 해안 단구로 정밀 조작함.
- **수계 내 건물 차단 및 지형 셰이더 보호:**
  - [BuildingRoadProcessor](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/building_road_processor.py)에서 `is_in_water()` 및 `base_y <= 0.2` 검사를 도입하여 수계 상의 건물 생성을 사전에 원천 차단함.
  - [building_road_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd)에 실시간 안전 가드를 적용하여 수계 내 건물 렌더링을 차단함(단, 간몬교 주탑 등 필수 해상 랜드마크는 예외 허용).
  - [procedural_terrain.gdshader](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/shaders/procedural_terrain.gdshader)에서 `water_mask < 0.05` 조건을 추가하여 하천/수역 구간에서 건물 및 도회지 텍스처가 섞이지 않도록 차단함.

## 4. 검증 결과
- **높이맵 생성:** `godot_project/assets/generated/kanmon_heightmap_16bit.png` (4096x4096 16비트) 자연 해안선 스무딩 적용 완료.
- **건물 데이터 검증:** 건물 36,094개, 도로 1,157개 정상 추출 완료. 수계 위 오인식 건물 0개(간몬교 해상 주탑 1개 정상 유지).
- **매니페스트 갱신:** `manifest.json`에 최신 SHA-256 및 메타데이터 갱신 완료.
