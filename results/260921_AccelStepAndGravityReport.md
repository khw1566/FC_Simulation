# [260921] 가속도 4단계 토글 및 컨트롤 연속클릭 중력 시스템 구현 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 개요 및 요구사항
- **가속도 단계식 토글:** 기존 연속 증감 방식에서 50 ~ 500 m/s² 범위를 4단계 프리셋으로 분할하여 직관적인 원터치 토글로 전환.
- **플레이어 중력 토글:** 컨트롤(Ctrl) 키 연속 2회 클릭(더블클릭) 시 자유 비행 모드와 지형 중력 작용 모드를 상호 전환.

---

## 2. 세부 구현 내역

### 2.1 가속도 4단계 순환 토글 시스템
- **프리셋 구성:**
  - 1단계: **50 m/s²** (정밀 조작 / 보행 탐색)
  - 2단계: **150 m/s²** (도심지 순항 가속)
  - 3단계: **300 m/s²** (고속 비행)
  - 4단계: **500 m/s²** (초고속 부스터 비행)
- **단축키:** `]` 또는 `X` (다음 단계), `[` 또는 `Z` (이전 단계)로 4단계를 순환 토글.

### 2.2 컨트롤(Ctrl) 더블클릭 중력 토글 시스템
- **동작 방식:** `KEY_CTRL` 입력을 감지하고 0.35초 이내 재입력 시 더블클릭으로 판정.
- **모드 전환:**
  - **중력 비활성 (OFF, 자유 비행 모드):** 상공에서 6자유도로 정지 및 E/Space(상승), Q/Ctrl(하강) 비행.
  - **중력 활성 (ON, 지상/물리 모드):** 지형 쪽으로 중력 가속도(9.8 m/s²)가 작용하여 낙하하며, Space 키로 점프/부스터 상승 수행.
- **HUD 실시간 연동:** 하단 상태바에 현재 중력 모드(`중력: ON (중력)` / `OFF (비행)`) 및 가속도 표출.

---

## 3. 수정 파일 목록
- [PlayerFlightController](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/player/player_flight_controller.gd): 가속도 프리셋 인덱싱 및 Ctrl 더블클릭 타이머 판정, 중력 물리 연산 통합.
- [SpeedHUDView](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/views/speed_hud_view.gd): 중력 상태 및 4단계 가속도 텍스트 레이아웃 갱신.
- [SpeedHUDController](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/controllers/speed_hud_controller.gd): `gravity_toggled` 시그널 및 다중 파라미터 연동.

---

## 4. 검증 결과
- Godot 4.3 헤드리스 엔진 구동 및 컴파일 검증 통과 (Exit Code 0).
