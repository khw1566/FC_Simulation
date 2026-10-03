# 260923_PauseSettingsAndMouseControlReport.md
작성일자: 2026-09-23
작성자: Antigravity

## 1. 개요 및 목적
본 보고서는 가상현실 렌더링 월드 진입 시 마우스 커서가 뷰포트 내에 고정되어 발생하는 조작 제약을 해소하고, `ESC` 키를 통한 일시 정지 메뉴/설정창 연동 및 `ALT` 키를 통한 한시적 마우스 릴리즈(Release) 상호작용 시스템의 구현 결과를 기술합니다.

## 2. 주요 엔지니어링 구현 내역
### 2.1 일시 정지 및 환경 설정 뷰 (`scripts/views/pause_settings_view.gd` & `scenes/pause_settings_hud.tscn`)
- 모노크롬 기본 테마: `#0a0a0a` 반투명 딤 오버레이 및 다크 그레이 카드 패널 구조를 적용하여 눈부심 방지 및 집중도 유지.
- 3대 핵심 액션 버튼:
  - 계속하기 (Resume): 시뮬레이션 일시 정지를 해제하고 뷰포트 마우스 캡처 모드로 즉각 복귀.
  - 환경 설정 (Settings): 마우스 시야 감도 슬라이더(0.001 ~ 0.01), MSAA 2x 안티앨리어싱 토글, 대기 안개(Fog) 토글, 실시간 태양 그림자 토글 제공.
  - 메인 화면 (Main Menu): 시뮬레이션을 중단하고 맵 선택 메뉴(`map_selection_menu.tscn`)로 즉시 안전 이동.
- 다국어 연동: 한국어 및 영어 모드에 맞추어 버튼 명칭, 타이틀, 설명 및 하단 조작 팁 자동 전환.

### 2.2 일시 정지 및 마우스 릴리즈 컨트롤러 (`scripts/controllers/pause_settings_controller.gd`)
- `PROCESS_MODE_ALWAYS` 설정: `get_tree().paused = true` 상태에서도 UI 입력과 버튼 이벤트가 정상 수신되도록 구성.
- `ESC` 키 핸들링:
  - `KEY_ESCAPE` 입력 감지 시 `toggle_pause()` 호출.
  - 정지 시: `get_tree().paused = true`, 마우스 커서 표시(`MOUSE_MODE_VISIBLE`), 딤 패널 노출.
  - 재개 시: `get_tree().paused = false`, 마우스 커서 캡처(`MOUSE_MODE_CAPTURED`), 딤 패널 숨김.
- `ALT` 키 홀드 기반 한시적 마우스 릴리즈:
  - 향후 HUD 상호작용(미니맵 확대, 버튼 조작 등)을 위해 `ALT` 키를 누르고 있는 동안 마우스 커서를 임시 해제(`MOUSE_MODE_VISIBLE`).
  - `ALT` 키에서 손을 떼면 즉시 비행 시야 조작 모드(`MOUSE_MODE_CAPTURED`)로 원복.

### 2.3 플레이어 비행 컨트롤러 최적화 (`scripts/player/player_flight_controller.gd`)
- 중복된 `ui_cancel` 마우스 토글 코드를 제거하고, 포즈 관리 권한을 `PauseSettingsController`로 일원화(Single Responsibility Principle).

## 3. 검증 결과
- Godot 4 엔진 구문 및 노드 파싱 무결성 검증 완료 (`Return Code: 0`).
- `ESC` 입력 시 시뮬레이션 일시 정지, 마우스 커서 활성화, 설정 변경 및 메인 메뉴 전환 기능 정상 작동 확인.
- `ALT` 키를 누르고 있는 동안 한시적으로 마우스 커서가 팝업되어 향후 HUD 상호작용 지원 가능 상태 확인.
