extends Control
class_name PauseSettingsView

## 일시 정지 메뉴 및 환경 설정 화면 뷰 (모노크롬 테마)
## 일반 / 컨트롤 탭 및 그래픽 탭 지원

signal resume_requested()
signal settings_requested()
signal main_menu_requested()
signal settings_back_requested()
signal sensitivity_changed(val: float)
signal msaa_toggled(enabled: bool)
signal fps_toggled(enabled: bool)
signal fog_toggled(enabled: bool)
signal shadows_toggled(enabled: bool)
signal flight_vector_toggled(enabled: bool)
signal vessels_toggled(enabled: bool)
signal industrial_zones_toggled(enabled: bool)
signal weather_toggled(enabled: bool)
signal weather_state_changed(state_index: int)
signal cloud_quality_changed(quality_index: int)
signal laptop_mode_requested()
signal time_changed(hours: float)
signal time_progression_toggled(enabled: bool)

@onready var pause_panel: PanelContainer = $RootMargin/MainLayout/PausePanel
@onready var settings_panel: PanelContainer = $RootMargin/MainLayout/SettingsPanel

# Pause Controls
@onready var pause_title_label: Label = $RootMargin/MainLayout/PausePanel/Margin/VBox/TitleLabel
@onready var pause_subtitle_label: Label = $RootMargin/MainLayout/PausePanel/Margin/VBox/SubtitleLabel
@onready var btn_resume: Button = $RootMargin/MainLayout/PausePanel/Margin/VBox/Buttons/BtnResume
@onready var btn_settings: Button = $RootMargin/MainLayout/PausePanel/Margin/VBox/Buttons/BtnSettings
@onready var btn_main_menu: Button = $RootMargin/MainLayout/PausePanel/Margin/VBox/Buttons/BtnMainMenu
@onready var hint_label: Label = $RootMargin/MainLayout/PausePanel/Margin/VBox/HintLabel

# Settings Controls
@onready var settings_title_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/TitleLabel
@onready var btn_tab_general: Button = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/TabHeader/BtnTabGeneral
@onready var btn_tab_graphics: Button = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/TabHeader/BtnTabGraphics
@onready var general_content: VBoxContainer = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent
@onready var graphics_content: VBoxContainer = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent

# General Tab Controls
@onready var sens_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/SensBox/SensHBox/SensLabel
@onready var sens_slider: HSlider = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/SensBox/SensSlider
@onready var sens_val_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/SensBox/SensHBox/SensValLabel
@onready var flight_vector_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/FlightVectorCheck
@onready var vessels_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/VesselsCheck
@onready var industrial_zones_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/IndustrialZonesCheck
@onready var weather_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/WeatherCheck
@onready var weather_state_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/WeatherStateRow/WeatherStateLabel
@onready var weather_state_option: OptionButton = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/WeatherStateRow/WeatherStateOption
@onready var time_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/TimeBox/TimeHBox/TimeLabel
@onready var time_val_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/TimeBox/TimeHBox/TimeValLabel
@onready var time_slider: HSlider = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/TimeBox/TimeSlider
@onready var time_progression_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GeneralContent/TimeProgressionCheck

# Graphics Tab Controls
@onready var cloud_quality_label: Label = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/CloudQualityRow/CloudQualityLabel
@onready var cloud_quality_option: OptionButton = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/CloudQualityRow/CloudQualityOption
@onready var btn_laptop_mode: Button = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/BtnLaptopMode
@onready var msaa_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/MsaaCheck
@onready var fps_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/FpsCheck
@onready var fog_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/FogCheck
@onready var shadow_check: CheckBox = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/GraphicsContent/ShadowCheck
@onready var btn_settings_back: Button = $RootMargin/MainLayout/SettingsPanel/Margin/VBox/BtnBack

const WEATHER_LABELS_KO: Array[String] = [
	"쾌청 (Clear)",
	"맑음/권운 (Cirrus Fair)",
	"구름 조금 (Partly Cloudy)",
	"흐림/덮개구름 (Overcast)",
	"짙은 안개 (Foggy)",
	"비 (Rain)",
	"뇌우 (Storm)"
]

const CLOUD_QUALITY_LABELS_KO: Array[String] = [
	"울트라 (Ultra - 28스텝 고품질)",
	"높음 (High - 16스텝 권장)",
	"보통 (Medium - 10스텝)",
	"노트북/경량 (Laptop - 5스텝 초경량)",
	"구름 끔 (Off)"
]

func _ready() -> void:
	_init_options()
	_init_button_events()
	_switch_tab(true)
	show_pause_menu()

func _init_options() -> void:
	if weather_state_option:
		weather_state_option.clear()
		for label in WEATHER_LABELS_KO:
			weather_state_option.add_item(label)
		weather_state_option.selected = 2

	if cloud_quality_option:
		cloud_quality_option.clear()
		for label in CLOUD_QUALITY_LABELS_KO:
			cloud_quality_option.add_item(label)
		cloud_quality_option.selected = 1  # 기본값: 높음 (High)

func _init_button_events() -> void:
	if btn_resume:
		btn_resume.pressed.connect(func(): resume_requested.emit())
	if btn_settings:
		btn_settings.pressed.connect(func():
			settings_requested.emit()
			show_settings_menu()
		)
	if btn_main_menu:
		btn_main_menu.pressed.connect(func(): main_menu_requested.emit())
	if btn_settings_back:
		btn_settings_back.pressed.connect(func():
			settings_back_requested.emit()
			show_pause_menu()
		)

	if btn_tab_general:
		btn_tab_general.pressed.connect(func(): _switch_tab(true))
	if btn_tab_graphics:
		btn_tab_graphics.pressed.connect(func(): _switch_tab(false))

	if sens_slider:
		sens_slider.value_changed.connect(func(v: float):
			if sens_val_label:
				sens_val_label.text = "%.3f" % v
			sensitivity_changed.emit(v)
		)
	if flight_vector_check:
		flight_vector_check.toggled.connect(func(b: bool): flight_vector_toggled.emit(b))
	vessels_check.toggled.connect(func(value: bool): vessels_toggled.emit(value))
	industrial_zones_check.toggled.connect(func(value: bool): industrial_zones_toggled.emit(value))
	if weather_check:
		weather_check.toggled.connect(func(b: bool):
			weather_toggled.emit(b)
			if weather_state_option:
				weather_state_option.disabled = not b
		)
	if weather_state_option:
		weather_state_option.item_selected.connect(func(idx: int): weather_state_changed.emit(idx))
	if time_slider:
		time_slider.value_changed.connect(func(v: float):
			update_time_display(v)
			time_changed.emit(v)
		)
	if time_progression_check:
		time_progression_check.toggled.connect(func(b: bool): time_progression_toggled.emit(b))

	# 그래픽 탭 이벤트
	fps_check.toggled.connect(func(b: bool): fps_toggled.emit(b))
	if cloud_quality_option:
		cloud_quality_option.item_selected.connect(func(idx: int): cloud_quality_changed.emit(idx))
	if btn_laptop_mode:
		btn_laptop_mode.pressed.connect(func():
			apply_laptop_preset_ui()
			laptop_mode_requested.emit()
		)
	if msaa_check:
		msaa_check.toggled.connect(func(b: bool): msaa_toggled.emit(b))
	if fog_check:
		fog_check.toggled.connect(func(b: bool): fog_toggled.emit(b))
	if shadow_check:
		shadow_check.toggled.connect(func(b: bool): shadows_toggled.emit(b))

func _switch_tab(is_general: bool) -> void:
	if general_content:
		general_content.visible = is_general
	if graphics_content:
		graphics_content.visible = not is_general

	# 버튼 하이라이트 표시
	if btn_tab_general:
		btn_tab_general.modulate = Color(1.2, 1.2, 1.2, 1.0) if is_general else Color(0.65, 0.65, 0.65, 1.0)
	if btn_tab_graphics:
		btn_tab_graphics.modulate = Color(1.2, 1.2, 1.2, 1.0) if not is_general else Color(0.65, 0.65, 0.65, 1.0)

func show_pause_menu() -> void:
	if pause_panel:
		pause_panel.visible = true
	if settings_panel:
		settings_panel.visible = false

func show_settings_menu() -> void:
	if pause_panel:
		pause_panel.visible = false
	if settings_panel:
		settings_panel.visible = true
	_switch_tab(true)

func update_localization(dict: Dictionary) -> void:
	if dict.is_empty():
		return
	if pause_title_label and dict.has("pause_title"):
		pause_title_label.text = dict["pause_title"]
	if pause_subtitle_label and dict.has("pause_subtitle"):
		pause_subtitle_label.text = dict["pause_subtitle"]
	if btn_resume and dict.has("btn_resume"):
		btn_resume.text = dict["btn_resume"]
	if btn_settings and dict.has("btn_settings"):
		btn_settings.text = dict["btn_settings"]
	if btn_main_menu and dict.has("btn_main_menu"):
		btn_main_menu.text = dict["btn_main_menu"]
	if hint_label and dict.has("alt_cursor_hint"):
		hint_label.text = dict["alt_cursor_hint"]
	if settings_title_label and dict.has("settings_title"):
		settings_title_label.text = dict["settings_title"]
	if sens_label and dict.has("settings_mouse_sens"):
		sens_label.text = dict["settings_mouse_sens"]
	if flight_vector_check and dict.has("settings_flight_vector"):
		flight_vector_check.text = dict["settings_flight_vector"]
	if dict.has("settings_vessels"):
		vessels_check.text = dict["settings_vessels"]
	if weather_check and dict.has("settings_weather"):
		weather_check.text = dict["settings_weather"]
	if weather_state_label and dict.has("settings_weather_state"):
		weather_state_label.text = dict["settings_weather_state"]
	if time_label and dict.has("settings_time_of_day"):
		time_label.text = dict["settings_time_of_day"]
	if time_progression_check and dict.has("settings_time_progression"):
		time_progression_check.text = dict["settings_time_progression"]
	if msaa_check and dict.has("settings_msaa"):
		msaa_check.text = dict["settings_msaa"]
	if fog_check and dict.has("settings_fog"):
		fog_check.text = dict["settings_fog"]
	if shadow_check and dict.has("settings_shadows"):
		shadow_check.text = dict["settings_shadows"]
	if btn_settings_back and dict.has("settings_back"):
		btn_settings_back.text = dict["settings_back"]

func apply_laptop_preset_ui() -> void:
	if cloud_quality_option:
		cloud_quality_option.selected = 3 # 노트북/경량 모드
	if shadow_check:
		shadow_check.button_pressed = false # 실시간 그림자 끔
	if msaa_check:
		msaa_check.button_pressed = false # MSAA 끔
	if fog_check:
		fog_check.button_pressed = true # 기본 안개는 유지

func update_time_display(hours: float) -> void:
	if time_slider and absf(time_slider.value - hours) > 0.05:
		time_slider.set_value_no_signal(hours)
	if time_val_label:
		var total_minutes := int(hours * 60.0)
		var hrs := (total_minutes / 60) % 24
		var mins := total_minutes % 60
		time_val_label.text = "%02d:%02d" % [hrs, mins]

func set_initial_settings(sens: float, msaa: bool, fog: bool, shadow: bool, flight_vector: bool = true, weather: bool = true, weather_state: int = 1, cloud_quality: int = 1, time_hours: float = 12.0, time_progression: bool = true, vessels: bool = true) -> void:
	vessels_check.set_pressed_no_signal(vessels)
	if sens_slider:
		sens_slider.set_value_no_signal(sens)
	if sens_val_label:
		sens_val_label.text = "%.3f" % sens
	if msaa_check:
		msaa_check.set_pressed_no_signal(msaa)
	if fog_check:
		fog_check.set_pressed_no_signal(fog)
	if shadow_check:
		shadow_check.set_pressed_no_signal(shadow)
	if flight_vector_check:
		flight_vector_check.set_pressed_no_signal(flight_vector)
	if weather_check:
		weather_check.set_pressed_no_signal(weather)
	if weather_state_option:
		weather_state_option.selected = weather_state
		weather_state_option.disabled = not weather
	if cloud_quality_option:
		cloud_quality_option.selected = cloud_quality
	if time_slider:
		time_slider.set_value_no_signal(time_hours)
	update_time_display(time_hours)
	if time_progression_check:
		time_progression_check.set_pressed_no_signal(time_progression)

