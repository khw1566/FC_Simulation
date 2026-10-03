# 260923_FlightVectorHUDReport.md
작성일자: 2026-09-23
작성자: Antigravity

## 1. 개요 및 목적
본 보고서는 향후 비행 시뮬레이션 시스템 고도화를 위하여 기체의 현재 비행 속도 벡터, 관성 진행 방향 및 수직 피치각을 화면 중앙에 직관적인 녹색(#00ff66) 화살표로 실시간 시각화하고, 환경 설정(Settings) 메뉴에서 자유롭게 On/Off 토글할 수 있는 벡터 HUD 시스템의 구축 내역을 기술합니다.

## 2. 주요 엔지니어링 구현 내역
### 2.1 비행 벡터 시각화 뷰 (`scripts/views/flight_vector_hud_view.gd` & `scenes/flight_vector_hud.tscn`)
- 2D Canvas Custom Drawing (`_draw()`):
  - 중앙 조준 레티클: 직경 24px의 원형 조준원과 정밀 크로스헤어를 화면 정중앙에 녹색 반투명 톤으로 렌더링.
  - 비행 속도 벡터 변환: 카메라 로컬 기준 기체 속도 성분(`local_x`: 좌우 횡이동, `local_y`: 상승/하강, `local_forward`: 전진 속도)을 스크린 2D 벡터로 사영.
  - 가변 길이 녹색 화살표: 기체 속도에 비례하여 화살표 몸체 및 삼각형 헤드(Arrowhead)가 동적으로 신장되며, 최대 240px 범위 내에서 부드럽게 보간(Lerp 12.0*delta) 처리.
  - 디지털 데이터 오버레이: 화살표 끝단에 현재 속도(`km/h`) 및 피치각(`°`) 정보를 녹색 고대비 텍스트로 실시간 표기.
- 마우스 필터: `MOUSE_FILTER_IGNORE` 설정으로 조작 간섭 배제.

### 2.2 환경 설정 연동 (`scripts/views/pause_settings_view.gd` & `scenes/pause_settings_hud.tscn`)
- 체크박스 추가: 설정 메뉴 내 `FlightVectorCheck`("비행 벡터 HUD (디버그 녹색 화살표)") 컨트롤 배치.
- 다국어 지원: 한국어 및 영어(`Flight Vector HUD (Green Arrow Debug)`) 동기화.
- 상태 초기화 및 시그널: `flight_vector_toggled(enabled: bool)` 시그널을 발행하여 사용자 선택 반영.

### 2.3 제어 컨트롤러 (`scripts/controllers/pause_settings_controller.gd`)
- `PauseSettingsController`에 `flight_vector_hud` 노드를 바인딩하고, 체크박스 토글 시 `flight_vector_hud.set_hud_visible(enabled)`를 호출하여 즉시 On/Off 제어.

## 3. 검증 결과
- Godot 4 엔진 구문 및 노드 파싱 무결성 확인 (`Return Code: 0`).
- 설정창 내 체크박스 토글을 통한 벡터 HUD의 실시간 표시/숨김 정상 작동 확인.
- 비행 조작 시 전진, 급상승, 횡방향 드리프트 상태에 따라 화면 중앙 녹색 화살표와 계측 텍스트가 기체 운동 벡터를 정밀하게 추종함을 확인.
