# 260927 울산 60km 광역 전역 간선 도로망 전수 수집 및 통합 보고서
작성일자: 2026-09-27
작성자: Antigravity AI

## 1. 개요
- 기존 울산 60km 광역맵에 포함되어 있던 도로 데이터는 울산대 캠퍼스 주변의 극히 일부(512개)에 불과하여 외곽 및 시가지 전역의 도로망이 누락되어 있던 문제를 해결함.
- 울산 광역권(60km x 60km, BBox: 35.2742~35.8148N, 128.9233~129.5877E) 전역의 실측 간선 도로망(고속도로, 국도, 주요 간선 및 보조 간선도로) 데이터를 Overpass API를 통해 전수 수집하고, 좌표 변환을 거쳐 [buildings_and_roads.json](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_metro_60km/buildings_and_roads.json)에 전면 통합 완료함.

## 2. 세부 작업 내역

### 2.1 도로망 수집 및 규격 분류
- **수집 대상:**
  - 경부고속도로, 울산고속도로, 동해고속도로, 함양울산고속도로 등 고속도로(`motorway`, 폭 22m)
  - 7번 국도, 14번 국도, 24번 국도, 31번 국도 등 국도 및 자동차전용도로(`trunk`, 폭 18m)
  - 삼산로, 번영로, 강남로, 강북로, 문수로, 염포로 등 시가지 주간선도로(`primary`, 폭 15m)
  - 구군간 연결 보조간선도로(`secondary`, 폭 12m) 및 집산도로(`tertiary`, 폭 9m)
- **수집 규모:**
  - 노드(Nodes): 79,725개
  - 연속 도로 선분(Ways): **8,878개** (기존 512개 대비 약 17.3배 확장)

### 2.2 60km 광역 월드 좌표계 변환 및 리본화
- 경위도 좌표계를 60,000m x 60,000m 기준의 Godot 3D 월드 중심 좌표계(`Vector3(wx, 0.0, wz)`)로 정밀 투영.
- 터널(`tunnel=yes`) 및 교량(`bridge=yes`) 속성을 도로 메타데이터에 보존하여 입체 교차로, 터널 갱구, 해협 횡단 교량 등이 절차적으로 정확하게 생성되도록 설정.

### 2.3 지형 노반 평탄화(Road Bed Grading) 연동
- 광역권 전역에 걸친 8,878개의 도로 리본이 런타임 시작 시 [terrain_chunk_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk_manager.gd)의 `_apply_road_bed_flattening_and_smoothing()`으로 전달되어, 산악 및 구릉지 도로의 지형을 자동으로 절토하고 평탄화하여 도로 매립 및 굴곡을 방지함.

## 3. 검증 결과
- **JSON 데이터 검증:** `building_count: 68,199`, `road_count: 8,878` 정상 갱신 확인.
- **Godot 4.3 헤드리스 검사:** `--check-only` 통과 (Exit Code: 0).
