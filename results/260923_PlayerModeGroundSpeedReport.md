날짜: 2026-09-23
작성자: khw (AI 엔지니어링 에이전트)

# 플레이어 모드 분리(디버그-비행 / 디버그-지상) 및 지상 속도 제어 구현 보고서

## 1. 개요 및 목적
플레이어 조작 상태를 '디버그-비행' 모드와 '디버그-지상' 모드로 명확히 분리하고, 지상 모드에서 발생하는 과도한 비행 속도와 관성 밀림 문제를 해결하기 위해 지상 환경에 최적화된 5단계 즉발(Instant) 속도 제어 체계를 구축하였습니다.

---

## 2. 플레이어 상태 정의 및 제어 사양

### 2.1. 상태 모드 분리
- **디버그-비행 (DEBUG_FLIGHT):**
  - 공중 자유 기동 및 초고속 광역 정찰을 위한 비행 물리 모드.
  - 가속도(`acceleration`) 및 관성 감속도(`deceleration`) 적용.
  - 최고속도 4단계 기어: 30 m/s (108 km/h) ~ 600 m/s (2,160 km/h).
  - 중력 기본 해제, 수직 이동(Space/E 상승, Ctrl/Q 하강).

- **디버그-지상 (DEBUG_GROUND):**
  - 보행, 차량 주행, 지표면 지형 및 건물 세밀 점검을 위한 지상 모드.
  - 이동 입력 시 **가속도 지연 없이 즉각 해당 속도로 직결 이동 (가속도 미적용 / 0ms 즉발 반응)**.
  - 입력 중단 시 관성 없이 즉시 정지 (`velocity.x = 0.0, velocity.z = 0.0`).
  - 이동 벡터를 수평면(`input_dir.y = 0.0`)으로 제한하여 시선 피치 각도에 따른 바닥 파고듦/공중 부양 방지.
  - 중력 자동 활성화 및 점프 기능(`Space`, 수직 속도 7.5 m/s) 지원.

### 2.2. 지상 모드 속도 5단계 (4 ~ 200 km/h)
- **1단:** 4 km/h (도보 및 정밀 건물 점검)
- **2단:** 20 km/h (조깅 / 자전거 주행 속도)
- **3단:** 60 km/h (일반 도로 도심 차량 주행)
- **4단:** 100 km/h (고속도로 주행 속도)
- **5단:** 200 km/h (고속 철도 및 초고속 지상 광역 순찰)

---

## 3. 변경 파일 목록 및 역할

- [player_flight_controller.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/player/player_flight_controller.gd)
  - `PlayerMode` enum (`DEBUG_FLIGHT`, `DEBUG_GROUND`) 정의.
  - `G` 키 입력을 통한 실시간 모드 상호 전환 구현.
  - 지상 모드 시 `GROUND_GEAR_SPEEDS_KMH` 기반 즉발 속도 제어 및 가속도 바이패스.
  - `speed_changed` 시그널에 `mode_name` 전달 추가.
- [speed_hud_view.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/views/speed_hud_view.gd)
  - HUD 기어 레이블에 현재 활성화된 모드(`[디버그-지상]`, `[디버그-비행]`) 표시.
  - 지상 모드일 때 가속도 수치 대신 `즉발 속도` 명시.
  - 속도 게이지 바의 기준 최대값을 모드별로 자동 분기 (지상 200km/h, 비행 2,160km/h).
- [speed_hud_controller.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/controllers/speed_hud_controller.gd)
  - 시그널 수신 시그니처에 `mode_name`을 추가하여 뷰와 완벽 동기화.
- [help_overlay_hud_view.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/views/help_overlay_hud_view.gd)
  - `F1` 도움말 조작 안내에 `G` 키 모드 전환 및 모드별 속도 기어 사양 반영.
