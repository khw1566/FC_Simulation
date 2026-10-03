# 260923_UlsanMapCleanupReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 울산과학대학교 서부캠퍼스 5km × 5km 맵에서 아직 공식 정밀 실측 데이터로 구축되지 않은 도로망 인프라 및 수계(해수면/하천) 레이어와 잘못된 타 맵 fallback 로드를 배제하고, 순수 VWorld 실측 3,000동 건물 풋프린트와 16비트 정밀 DEM 등고선 지형으로 정제한 조치 결과를 기록합니다.

## 2. 세부 조치 내역
1. **타 맵 수계/해안선 오작동 fallback 차단 ([coastline_waterway_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/water/coastline_waterway_manager.gd)):**
   - 울산 맵 선택 시 기존 칸몬 해협의 수로 및 해안선 데이터가 자동 fallback 로드되던 취약점을 제거하고, 해당 맵 전용 벡터가 없는 경우 렌더링을 완전히 건너뛰도록 격리 조치함.
2. **해수면 평면(Sea Plane) 비활성화 ([kanmon_water_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/water/kanmon_water_manager.gd)):**
   - 내륙 구릉지형인 울산과학대 권역 특성에 맞추어 [map_meta.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/map_meta.json)의 `sea_level`을 `-999.0`으로 설정.
   - `KanmonWaterManager`에서 `sea_level <= -900.0`인 경우 불필요한 해수면 평면 생성을 원천 차단함.
3. **건물 및 전술 지도 정제 ([buildings_and_roads.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/buildings_and_roads.json) / [ulsan_vector_tactical_map.png](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/ulsan_vector_tactical_map.png)):**
   - 도로망(`roads: []`) 및 터널(`tunnels: []`)은 미구현 상태로 공백을 유지.
   - 미니맵 및 M키 전체화면 지도 텍스처에서 미검증 수계 블렌딩을 제거하고, 순수 실측 고도 등고선(20m 주곡선/간곡선)과 VWorld 실측 3,000동 건물 풋프린트만으로 깔끔하게 전술 지도를 재렌더링함.
4. **자산 매니페스트 갱신:**
   - [manifest.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/manifest.json)에 정제된 자산 SHA-256 해시 인덱싱 완료.
