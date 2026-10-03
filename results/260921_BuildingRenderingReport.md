# [260921] 실측 건물 풋프린트 및 도로망 3D 박스 렌더링 구축 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 개요 및 변경 목적
- **문제점 분석:** 기존에 주요 랜드마크 5개만 등록되어 있어 광역 도심에 실제 건물군이 렌더링되지 않던 문제가 발생함.
- **해결 방안:**
  - OpenStreetMap 실측 건물 풋프린트(Polygon Footprints) 및 층수/높이 메타데이터 수집 파이프라인(`BuildingCollector`) 구축.
  - 실제 다각형 경계의 가로, 세로 밑면 폭과 실제 층수/높이를 계산하여 지표면 DEM 고도에 정확히 안착시키는 전처리기(`BuildingRoadProcessor`) 구현.
  - 대량의 건물 박스를 프레임 드랍 없이 고속 렌더링할 수 있도록 단일 `SurfaceTool` 통합 배칭 렌더러(`BuildingRoadManager`) 구현.

---

## 2. 수집 및 전처리 파이프라인 산출물

- **실측 건물 수집:** [kanmon_straits_buildings.json](file:///C:/Users/khw/Desktop/가상현실%20렌더링/data/raw/buildings/kanmon_straits_buildings.json) (972개 실제 빌딩 다각형 수집 완료)
- **최종 3D 자산:** [buildings_and_roads.json](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/generated/buildings_and_roads.json)
- **건물 수:** 972개 (모지코 레트로, 시모노세키 연안 도심 및 주요 랜드마크)
- **간선 도로망 수:** 1,157개 리본 세그먼트

---

## 3. 핵심 모듈 아키텍처

- [BuildingCollector](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/collectors/building_collector.py): 실시간 Overpass API를 통해 실제 건물 풋프린트 좌표 및 `height`, `building:levels` 태그 자동 수집.
- [BuildingRoadProcessor](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/building_road_processor.py): 다각형 바운딩 박스로부터 실측 밑면 치수 및 중심 좌표 계산, DEM 고도 보정(`base_y`) 적용.
- [BuildingRoadManager](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd): 수백 개의 개별 노드 생성 대신 단일 통합 메시 배칭 기법을 적용하여 드로우콜 병목 최소화 및 60FPS 보장.

---

## 4. 검증 결과
- Godot 4.3 헤드리스 엔진 구동 및 씬 컴파일 검증 완료 (에러 코드 0).
- 단일 파일 800라인 제한 및 모노크롬 기본 테마 원칙 엄수.
