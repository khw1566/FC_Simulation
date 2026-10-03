# [260921] 지하 10m 터널 입체 튜브 렌더링 및 통과 판정 구현 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 개요 및 요구사항 반영
- **요구사항 분석:**
  - 도로 선형이 지형 표면 대비 10m 이하 깊이로 파묻히는 구간을 입체적인 3D 터널(아치 튜브 구조체)로 시각화.
  - 플레이어가 비행 또는 주행 중 해당 터널을 지날 때 지형 메시에 막히지 않고 자연스럽게 내부를 관통할 수 있도록 예외적 충돌 무효화(Passage) 기능 구현.
- **해결 방안:**
  - **파이프라인 터널 자동 판출 ([BuildingRoadProcessor](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/building_road_processor.py)):**
    - OSM 태그(`tunnel=yes`) 및 각 도로 정점의 지표면 DEM 고도와 도로 중심선 간 깊이 차이(≥ 10m)를 정밀 분석하여 터널 구간(총 107개 세그먼트)을 자동 분류.
    - 터널 구간은 산악 내부를 자연스럽게 관통하도록 입·출구 표고를 기준으로 한 선형 관통 고도를 산출하여 기록.
  - **터널 3D 입체 아치 렌더링 ([BuildingRoadManager](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd)):**
    - 터널로 판정된 도로 구간에 대해 폭 12m, 높이 7m의 콘크리트 라이닝 아치 튜브(좌벽, 우벽, 천장)를 별도의 `SurfaceTool`로 배칭 렌더링.
    - 터널 선분들을 실시간 공간 인덱스(`tunnel_segments`)로 등록.
  - **플레이어 터널 예외 통과 시스템 ([PlayerFlightController](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/player/player_flight_controller.gd)):**
    - 매 물리 프레임마다 플레이어의 좌표가 터널 반경(14m) 및 높이 범위 내에 있는지 실시간 판정(`is_position_inside_tunnel()`).
    - 터널 진입 시 지형 충돌체(`CollisionShape3D`)를 일시 비활성화하여 산악 지형 내부를 막힘없이 통과하도록 처리하고, 탈출 시 원래 충돌 상태를 즉시 복원.

---

## 2. 모듈별 세부 구현 내역

| 모듈 | 주요 역할 및 변경 내역 |
| :--- | :--- |
| **BuildingRoadProcessor** | 10m 이상 지하 매설 판정 및 산악 내부 관통 고도 계산, JSON 내 `is_tunnel` 플래그 및 `tunnels` 리스트 분리 내보내기 |
| **BuildingRoadManager** | 터널 전용 `tunnel_wall_material` 적용, 아치형 튜브 메시 배칭 렌더링 및 `is_position_inside_tunnel()` 공간 검색 엔진 탑재 |
| **PlayerFlightController** | `_check_tunnel_exception()` 메서드를 통해 터널 구역 진입 감지 및 지형 충돌 예외 무효화/복원 자동화 |

---

## 3. 검증 결과
- 터널 판정 및 JSON 데이터 정상 생성: 총 107개 터널 구간 분류 완료.
- Godot 4.3 헤드리스 엔진 프로젝트 컴파일 검증 통과 (Exit Code 0).
