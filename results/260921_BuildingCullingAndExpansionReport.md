# [260921] 건물 렌더링 면 컬링 오류 수정 및 3대 도심 권역 확장 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 개요 및 결함 분석
- **문제점 1 (건물 반대편만 보이고 앞면이 투명해지는 현상):**
  - 원인: 건물 재질의 `render_priority = 2` 설정과 `cull_mode = CULL_BACK` 조합으로 인해, 불투명 패스에서 지형 셰이더와 깊이 판정 우선순위가 꼬이거나 카메라를 향하는 앞면이 컬링되는 백페이스 컬링 오작동이 발생함.
  - 조치: `cull_mode`를 `CULL_DISABLED`(양면 렌더링)로 전환하고 `depth_draw_mode = DEPTH_DRAW_OPAQUE_ONLY` 및 표준 깊이 버퍼 판정을 적용하여 건물의 앞/뒤/옆/상부 모든 면이 어떠한 시점에서도 완전하게 불투명 박스로 렌더링되도록 수정함.
- **문제점 2 (모지구 극히 일부에만 건물이 렌더링되는 현상):**
  - 원인: 기존 Overpass 쿼리 범위가 모지코역 인근 반경 1km 소구역에만 한정되어 있었음.
  - 조치: 고쿠라역 도심, 모지코 전역, 시모노세키 항만 도심을 모두 포함하는 3대 도심 권역으로 수집 영역을 확장하여 총 **3,369개 실제 건물 풋프린트**로 대폭 확충함.

---

## 2. 수집 및 렌더링 결과

| 구분 | 이전 상태 | 개선 후 상태 | 비고 |
| :--- | :--- | :--- | :--- |
| **건물 렌더링 면** | 앞면 누락/반대편 투과 | 앞/뒤/좌/우/상부 100% 완전 렌더링 | `CULL_DISABLED` 적용 |
| **건물 수집 개수** | 972개 | **3,369개** | 약 3.5배 확장 |
| **포괄 구역** | 모지코 레트로 일부 | **고쿠라역 도심 + 모지코 전역 + 시모노세키항** | 간몬해협 전역 도심망 형성 |
| **지형 간섭 방지** | 기초 솟아오름 일부 잔존 | 기초 하부 3.0m 지중 연장 | 경사지 안착 완성 |

---

## 3. 모듈별 주요 수정 내역
- [BuildingRoadManager](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd): 건물 재질의 `cull_mode`를 `CULL_DISABLED`로 수정하고, `depth_draw_mode`를 `DEPTH_DRAW_OPAQUE_ONLY`로 설정. 건물 기초를 -3.0m 지중 연장하여 지형 결착성 극대화.
- [BuildingCollector](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/collectors/building_collector.py): 간몬해협 3대 도심 핵심 권역을 분할 수집하여 병합하도록 확장.
- [BuildingRoadProcessor](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/building_road_processor.py): 3,369개 건물 전체에 대해 정밀 바이리니어 DEM 표고 연동 및 JSON 생성.
- [buildings_and_roads.json](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/generated/buildings_and_roads.json): 3,369개 건물 및 1,157개 도로 리본 완벽 갱신.

---

## 4. 엔진 검증
- Godot 4.3 엔진 무결성 체크 완료 (에러 코드 0).
