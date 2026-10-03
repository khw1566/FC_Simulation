# 날짜: 2026-09-26
# 작성자: khw (AI 엔지니어링 어시스턴트)

# 창 포커스 전환(Alt+Tab/최소화) 시 마우스 커서 자동 해제 구현 완료 보고서

## 1. 개요 및 목적
게임 실행 중 마우스가 `MOUSE_MODE_CAPTURED` 상태로 고정되어 있을 때, 게임 창이 최소화되거나 Alt+Tab 등으로 다른 윈도우 창으로 전환 시 마우스 커서가 게임 틀 안에 갇히지 않고 자유롭게 데스크톱 및 다른 프로그램을 조작할 수 있도록 윈도우 포커스 감지 및 마우스 릴리즈 시스템을 구현하였습니다.

---

## 2. 주요 변경 사항 및 동작 원리

### 2.1 윈도우 OS 포커스 이벤트 수신 (`pause_settings_controller.gd`)
- **`_notification(what: int)` 핸들러 구현:**
  - `NOTIFICATION_APPLICATION_FOCUS_OUT`, `NOTIFICATION_WM_WINDOW_FOCUS_OUT`:
    - 게임 창이 포커스를 잃거나 최소화될 때 OS 알림을 즉시 감지하여 마우스 모드를 `Input.MOUSE_MODE_VISIBLE`로 자동 전환.
    - 이를 통해 Alt+Tab 전환, 작업 표시줄 클릭, 듀얼 모니터 이동 시 마우스 커서가 완전히 자유로워짐.
  - `NOTIFICATION_APPLICATION_FOCUS_IN`, `NOTIFICATION_WM_WINDOW_FOCUS_IN`:
    - 사용자가 다시 게임 창을 클릭하거나 선택하여 포커스가 돌아왔을 때, 일시정지(`ESC`) 메뉴가 열려있지 않거나 Alt 키를 누르고 있지 않다면 자동으로 `Input.MOUSE_MODE_CAPTURED`로 복귀하여 원활한 비행 조작을 재개.

### 2.2 게임 복귀 편의성 보강 (`player_flight_controller.gd`)
- 창 복귀 후 마우스 좌/우클릭 시 일시정지 상태가 아니라면 즉시 마우스를 다시 게임 컨트롤러에 캡처(`MOUSE_MODE_CAPTURED`)하도록 `_unhandled_input`에 안전 로직 추가.

---

## 3. 검증 결과
- Godot 4.3 stable 헤드리스 씬 및 스크립트 컴파일 문법 검사 결과 정상 통과(Exit Code 0).
- Alt+Tab 및 창 포커스 이탈 시 마우스 커서 릴리즈가 정상적으로 작동하도록 구성 완료.
