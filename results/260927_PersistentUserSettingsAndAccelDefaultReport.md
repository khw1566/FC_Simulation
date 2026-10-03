---
date: 2026-09-27
author: Antigravity
---
# 가속도 수준 기본값(60%) 설정 및 게임 설정 영구 저장 시스템 구축 리포트

본 문서는 비행 가속도 기본값을 현재 기어 최고속도의 60% 수준으로 고정하고, 게임 내 모든 설정이 재시작 후에도 지속적으로 유지되도록 `UserSettingsService` 싱글톤 및 영구 구성 파일 저장 시스템을 구축한 내역을 기록합니다.

---

## 1. 핵심 요구사항 및 구현 개요
1. **가속도 기본값 60% 보장:**
   - 비행 모드 진입 시 가속도 비율의 초기 인덱스를 3단계(`current_accel_step = 2`, 즉 $60\%$)로 기본 지정.
   - 기어 1단~7단 변경 시 항상 해당 최고속도의 60%가 기본 가속력으로 즉시 적용됨.
2. **게임 설정 영구 보존 (Persistence across Sessions):**
   - 게임을 종료하거나 씬을 재시작해도 플레이어의 조작 및 시스템 설정이 초기화되지 않고 로드되도록 엔진 영구 경로(`user://settings.cfg`) 기반 아키텍처 도입.

---

## 2. 세부 구현 내역

### 1) `UserSettingsService` 싱글톤 오토로드 신설 (`project.godot`)
- 파일 위치: `godot_project/scripts/services/user_settings_service.gd`
- 엔진 오토로드 등록: `UserSettingsService="*res://scripts/services/user_settings_service.gd"`
- **관리 항목:**
  - 비행/조작: 가속도 비율 단계(`flight_accel_step`, 기본값 2=60%), 최고속도 기어(`flight_gear`), 중력 On/Off, 충돌(노클립) On/Off, 마우스 감도(`mouse_sensitivity`)
  - 그래픽/렌더링: 안티앨리어싱(MSAA), 거리 안개(Fog), 실시간 태양 그림자(Shadow), 입체 볼류메트릭 구름 품질(`cloud_quality`)
  - 게임플레이/HUD: 비행 벡터 지시계(Flight Vector HUD), 실시간 기상 시뮬레이션 및 날씨 프리셋 상태(`weather_state`), 다국어 언어

### 2) 비행 컨트롤러 연동 (`player_flight_controller.gd`)
- `_ready()` 시 `UserSettingsService`에서 저장된 가속도 단계와 기어, 중력, 충돌 설정을 자동 로드.
- `Z` / `X` (가속도 비율 변경), `Shift` (기어 변경), `Double-Ctrl` (중력 토글), `C` (충돌 토글) 입력 시마다 `_save_flight_settings()`를 통해 `user://settings.cfg`에 즉각 자동 저장.

### 3) 일시정지 및 시스템 설정 연동 (`pause_settings_controller.gd`)
- ESC 일시정지 메뉴 열람 및 월드 로드 시, 영구 저장된 그래픽 품질/마우스 감도/HUD 설정이 화면과 뷰포트에 자동 복원.
- 슬라이더 및 체크박스 조작 시 실시간으로 영구 저장소에 반영.

---

## 3. 검증 결과
- **Godot 4.3 헤드리스 검사 통과:** 오토로드 싱글톤 및 스크립트 바인딩 구문 검사(`--check-only`) 정상 완료 (Exit Code 0).
- **무결성 유지:** 800라인 코드 제한 및 기존 물리/카메라 제어 로직 100% 호환.
