# 260922_CoastlineAndEstuaryRenderingReport.md
날짜: 2026-09-22
작성자: Antigravity AI Engineering Team

## 1. 문제 분석 및 배경
- **래스터 해안선 번짐(Bleed) 및 아티팩트:** 기존 `water_mask_texture` 생성 시 해양 외곽선(Coastline)이 2픽셀 두께의 래스터 라인으로 겹쳐 렌더링되면서, 바다 표면과 해안가 육지 경계면에서 수계 셰이더와 육상 셰이더가 충돌하여 지저분한 얼룩 및 계단 현상이 발생하였습니다.
- **하천-해양 접점(기수역) 불연속성:** 하천 마스크는 고도 0.5m 이상에서만 단절되어 작동하고 있어, 강이 해수면(Y = 0.0m)과 만나는 삼각주/하구에서 수면 색상과 수심이 자연스럽게 이어지지 못하고 절벽처럼 끊어지는 문제가 있었습니다.

## 2. 해결 방안 및 구현 규칙
1. **래스터 수계 마스크 정제:**
   - [`watermask_processor.py`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/watermask_processor.py) 로직을 수정하여 수계 마스크에는 순수 내륙 하천/호수 폴리곤만 보존하고 해양 해안선(Coastline) 래스터 번짐을 완전 격리하였습니다.
2. **별도 벡터 해안선 및 하천 데이터셋 구축:**
   - OpenStreetMap의 정밀 실측 벡터를 파싱하여 [`coastlines_and_waterways.json`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/kanmon_straits/coastlines_and_waterways.json) 파일로 독립 생성하였습니다.
   - 각 정점의 3D 월드 좌표(X, Z)와 수치표고모델(DEM) 기반 고도(Y)를 정밀 매핑하였습니다.
   - 칸몬 해협(28km) 기준 해안선 세그먼트 95개, 하천 수로 세그먼트 351개를 확보하였으며 시모노세키 3km 정밀 맵에도 로컬 좌표 변환을 거쳐 동기화하였습니다.
3. **지형 및 해수면 셰이더 기수역 규칙 도입:**
   - [`procedural_terrain.gdshader`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/shaders/procedural_terrain.gdshader): 하천 수면이 해발 -0.2m ~ 1.5m 대역에서 해수면 바닥색(`sea_bottom_color`)과 부드럽게 보간(Estuary Blend)되도록 개선하여 강과 바다가 하나로 이어지도록 처리하였습니다.
   - [`kanmon_water.gdshader`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/shaders/kanmon_water.gdshader): 깊이 버퍼(`depth_texture`) 기반 수심 차이를 세분화하여, 수심 0.1m ~ 1.5m 사이에서만 미세 포말(Foam)을 형성하고 얕은 해안선에서는 알파 페이드가 이루어지도록 튜닝하였습니다.
4. **벡터 기반 완충대 렌더러 구현:**
   - [`CoastlineWaterwayManager`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/water/coastline_waterway_manager.gd) 신규 클래스를 제작하여 해안선 완충 리본(8m 폭)과 하천 수로 리본을 배치 단위로 실시간 생성·배치하였습니다.

## 3. 검증 결과
- Godot 4.3 헤드리스 엔진 실행 결과, 칸몬 해협 맵 진입 시 95개 해안선 리본과 351개 하천 수로가 지형 위에 안착하며 오류 없이 렌더링됨을 확인하였습니다.
