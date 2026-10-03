# 260923_UlsanVectorMapAndHudReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 울산과학대학교 서부캠퍼스 5km × 5km 권역의 VWorld 실측 건물 풋프린트 데이터를 2D 벡터 이미지(SVG)로 시각화하고, 게임 내 좌측 상단 미니맵 및 M키 전체화면 전술 지도 뷰에 울산 맵의 지도 텍스처와 실시간 좌표계가 정상 반영되도록 개선한 결과를 기록합니다.

## 2. 건물 벡터 SVG 시각화
- **프로세서 개발:** [UlsanVectorMapGenerator](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/ulsan_vector_map_generator.py) 구현.
- **벡터 SVG 자산 생성:**
  - 파일: `godot_project/assets/maps/ulsan_uc_west/building_footprints.svg`
  - 울산 무거동 VWorld 실측 3,000동 건물 다각형(Polygon)을 2048 × 2048 해상도의 W3C 표준 SVG 벡터로 변환.
  - 건물별 층수(`data-floors`), 고유관리번호(`data-sn`), 건물명(`data-name`) 메타데이터를 SVG 속성으로 인코딩.
  - 층수 비례 밝기 단계(모노크롬 테마 준수)로 건물별 명도 차등 시각화.
- **인덱스 매니페스트:**
  - 파일: `godot_project/assets/maps/ulsan_uc_west/building_footprints_index.json` (3,000동 건물 색상 및 메타 인덱스).

## 3. 미니맵 및 M키 전체화면 지도 텍스처 연동
- **전술 래스터 지도 생성:**
  - 파일: `godot_project/assets/maps/ulsan_uc_west/ulsan_vector_tactical_map.png` (2048 × 2048 RGBA)
  - 울산 5km 권역 실측 등고선(20m 간격 주곡선/간곡선), 태화강 및 무거천 지류 수역 마스크, VWorld 실측 3,000동 건물 밑면 다각형을 정밀 중첩 렌더링.
- **HUD 뷰어 동적 연동 보강 ([map_hud_view.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/views/map_hud_view.gd)):**
  - 기존 하드코딩되거나 누락되었던 전술 지도 경로(`tactical_map_path`)를 [map_meta.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/map_meta.json)에 정식 등록.
  - `MapHUDView._init_from_map_selection()`에서 현재 선택된 맵의 실측 바운딩 박스(BBox: 35.5220~35.5670°N, 129.2279~129.2831°E)와 월드 크기(5,000m)를 [GeoCoordinateConverter](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/core/geo_coordinate_converter.gd)에 실시간 주입.
  - 좌측 상단 미니맵 및 M키 전체화면 지도에서 울산 5km 지도가 정확한 비율(1km 로컬 뷰포트 확대)과 플레이어 마커/시야각(FOV) 콘으로 실시간 연동되도록 조치.
