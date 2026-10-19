extends Control
class_name HelpOverlayHUDView

## F1 도움말 오버레이 뷰
## ESC 메뉴와 별개로 언제든지 F1 키로 즉시 표시/숨김 토글

@onready var root_panel: PanelContainer = $RootPanel
@onready var title_label: Label = $RootPanel/Margin/VBox/TitleLabel
@onready var content_label: Label = $RootPanel/Margin/VBox/ContentLabel
@onready var close_hint_label: Label = $RootPanel/Margin/VBox/CloseHintLabel

var _is_visible: bool = false
var _current_lang: String = "ko"

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func toggle_help(lang: String = "ko") -> void:
	_current_lang = lang
	_is_visible = not _is_visible
	visible = _is_visible
	if _is_visible:
		_refresh_content()

func set_lang(lang: String) -> void:
	_current_lang = lang
	if _is_visible:
		_refresh_content()

func _refresh_content() -> void:
	if _current_lang == "en":
		_set_english_content()
	else:
		_set_korean_content()

func _set_korean_content() -> void:
	if title_label:
		title_label.text = "조작 안내"
	if content_label:
		content_label.text = """[상태 모드 및 이동]
  G              플레이어 상태 전환 (디버그-비행 <-> 디버그-지상)
  W / S / A / D  전진 / 후진 / 좌 / 우 이동
  Space          상승 (비행 모드) / 점프 (지상 모드)
  Shift          기어 단계 변경
                 - 비행: 1단~7단 (108 ~ 12,240 km/h [Mach 10], 가속도 적용)
                 - 지상: 1단~5단 (4, 20, 60, 100, 200 km/h, 즉발 반응)
  Z / X          비행 가속도 5단계 조절 (최고속도의 20%, 40%, 60%, 80%, 100%)

[물리 및 비행 설정]
  Ctrl x2        중력 작용 On / Off
  C              충돌 감지 On / Off (노클립)
  TAB            고도별 기상 상세 및 대기역학/마하수 HUD 토글

[지도 및 시스템]
  M              전체화면 전술 지도 열기 / 닫기
  T              지형 스타일 토글 (위성 피복 <-> 등고선)
  [ / ]          시간대 1시간 즉각 변경 (낮밤/태양 궤적 즉각 반영)
  ESC            일시 정지 및 시스템 설정 메뉴 (시간 슬라이더 조절)
  Alt (홀드)     마우스 커서 임시 활성화
  F1             도움말 오버레이 토글
  F2             맵 선택 메인 메뉴로 복귀
  F9             커스텀 오브젝트 열람 (회전·확대·부재 선택)
  F10            화면 중앙 대상 및 좌표 디버그

[핵폭발 시뮬레이션]
  B              위력 순환 (10kt / 50kt / 500kt / 1Mt / 10Mt)
  V              조준점(시선-지형 교차) 상공에서 투하
  K              모든 폭발·낙하 중 폭탄 제거"""
	if close_hint_label:
		close_hint_label.text = "F1 - 닫기"

func _set_english_content() -> void:
	if title_label:
		title_label.text = "CONTROLS"
	if content_label:
		content_label.text = """[PLAYER MODE & MOVEMENT]
  G              Toggle Player Mode (Debug-Flight <-> Debug-Ground)
  W / S / A / D  Move Forward / Backward / Left / Right
  Space          Ascend (Flight) / Jump (Ground)
  Shift          Cycle Speed Gear:
                 - Flight: Gear 1~4 (108 ~ 2160 km/h, Acceleration applied)
                 - Ground: Gear 1~5 (4, 20, 60, 100, 200 km/h, Instant response)
  Z / X          Adjust Acceleration (Flight mode only)

[PHYSICS & NAVIGATION]
  Ctrl x2        Toggle Gravity
  C              Toggle Collision (Noclip)
  TAB            Atmosphere / Mach Speed HUD

[MAP & SYSTEM]
  M              Toggle Tactical Map
  T              Toggle Terrain Style (Satellite <-> Simple)
  [ / ]          Adjust Time of Day (+/- 1 Hour, Instant Day/Night)
  ESC            Pause & Settings Menu (Time of Day Slider)
  Alt (Hold)     Show Cursor for HUD
  F1             Toggle this Help Overlay
  F2             Return to Map Selection Menu
  F9             Custom Object Inspector
  F10            World Object Debug Overlay

[NUCLEAR DETONATION]
  B              Cycle Yield (10kt / 50kt / 500kt / 1Mt / 10Mt)
  V              Drop on Aim Point (view ray / terrain)
  K              Clear All Detonations and Bombs"""
	if close_hint_label:
		close_hint_label.text = "F1 - Close"
