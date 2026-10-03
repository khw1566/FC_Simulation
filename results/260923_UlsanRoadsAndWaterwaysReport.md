# 260923_UlsanRoadsAndWaterwaysReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 디지털 트윈국토(VWorld) 국가공간정보 Data API 2.0(`LT_L_SPRD`) 및 실측 수계 지리정보를 연동하여, 울산과학대학교 서부캠퍼스 5km × 5km 권역의 정밀 실측 도로망과 태화강 및 무거천 지류 수계(하천망)를 3D 리본 메쉬로 가공 및 배치한 결과를 기록합니다.

## 2. 수집 및 가공 내역
1. **VWorld 도로명주소 도로구간 전수 수집 및 3D 노면 고도 일치 ([ulsan_infra_processor.py](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/ulsan_infra_processor.py)):**
   - VWorld `LT_L_SPRD` API를 통해 무거동 및 대학로 일대 도로구간 512개 전수 수집 완료.
   - 도로 등급별 차폭 차등화(대로/로: 14m, 길: 8m).
   - DEM 표고 보간을 통해 노면 고도(`terrain_y + 0.4m`)를 밀착 산출하여 지형 파묻힘 및 Z-fighting 방지.
   - 산출물: `godot_project/assets/maps/ulsan_uc_west/buildings_and_roads.json` 내 `roads: 512개` 병합 완료.
2. **태화강 본류 및 무거천/척과천 실측 하천 수계 구축:**
   - 태화강 본류(폭 75m) 및 지류 하천(폭 18m) 52개 유로 벡터 생성.
   - 지표면 표고 밀착(`terrain_y + 0.25m`) 및 유려한 물결 수면 셰이더 연동.
   - 산출물: `godot_project/assets/maps/ulsan_uc_west/coastlines_and_waterways.json` 내 `waterways: 52개` 수로 채널 생성 완료.
3. **Godot 4 맵 시스템 연동:**
   - [map_meta.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/map_meta.json)에 `coastlines_waterways` 경로 등록.
   - [coastline_waterway_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/water/coastline_waterway_manager.gd) 및 [building_road_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd)에서 울산 5km 맵 선택 시 512개 도로 리본과 52개 수로 채널 자동 로드 및 실시간 렌더링 검증 완료.
