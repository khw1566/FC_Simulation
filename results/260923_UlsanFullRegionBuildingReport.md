# 260923_UlsanFullRegionBuildingReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 기존 무거동 중심부(약 2.5km × 2.5km, 3,000동)에 한정되어 외곽 건물이 잘리던 문제를 해결하고, 울산과학대학교 서부캠퍼스를 중심으로 한 5km × 5km(-2,500m ~ +2,500m) 전체 권역을 대상으로 VWorld 디지털 트윈국토 실측 건물을 전수 수집 및 3D 배치한 결과를 기록합니다.

## 2. 분할 수집 전략 및 기술적 조치
- **API 10㎢ 요청 제약 극복:**
  - VWorld Data API 2.0의 1회 조회 면적 제한(10㎢ 이하)을 준수하기 위해, 5km × 5km(25㎢) 전체 바운딩 박스를 **2 × 2 그리드(각 셀 약 6.25㎢)**로 세분화함.
- **수집기 개선 ([vworld_building_collector.py](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/collectors/vworld_building_collector.py)):**
  - `fetch_full_region_grid()`를 구현하여 4개 셀을 순회하며 국가공간정보 고유식별자(`bd_mgt_sn`) 기준으로 중복 없이 총 8,111건의 원본 건물 다각형을 전수 수집함.
- **기존 도로망 보존 병합 ([vworld_building_processor.py](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/vworld_building_processor.py)):**
  - 기존 구축된 512개 실측 도로망을 안전하게 보존 병합하여 건물과 도로가 완벽히 결합된 `buildings_and_roads.json`을 완성함.

## 3. 구축 및 검증 결과
- **총 유효 건물 수:** 8,076동 (기존 3,000동 대비 약 2.7배 확장)
- **보존 도로 수:** 512개 실측 도로 구간
- **공간 커버리지 검증:**
  - X축 범위: `-2,497.5m ~ +2,500.1m` (5km 전체 폭 완벽 커버)
  - Z축 범위: `-2,500.6m ~ +2,505.4m` (5km 전체 높이 완벽 커버)
  - 경계면 잘림 현상(사각 클리핑) 전면 해소.
- **2D 벡터 SVG 및 전술 지도 갱신:**
  - `godot_project/assets/maps/ulsan_uc_west/building_footprints.svg`: 8,076동 전수 벡터화 완료.
  - `godot_project/assets/maps/ulsan_uc_west/ulsan_vector_tactical_map.png`: 5km 전역 등고선 및 건물 반영 완료.
  - `manifest.json`: 최신 해시 인덱싱 완료.
