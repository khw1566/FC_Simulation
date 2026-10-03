extends Node
class_name PauseSettingsController

## 일시 정지 메뉴 및 시스템 설정 관리 컨트롤러

@export var pause_view: Control
@export var player_node: CharacterBody3D
@export var world_environment: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var flight_vector_hud: Control
@export var weather_manager: Node3D
@export var help_overlay_hud: Control
@export var day_night_service: Node

var _translations: Dictionary = {}
var _is_paused: bool = false
var _alt_held: bool = false
var _flight_vector_enabled: bool = true
var _weather_enabled: bool = true
var _weather_state: int = 2  # 0=Clear 1=Cirrus 2=PartlyCloudy 3=Overcast 4=Foggy 5=Rain 6=Storm
var _time_hours: float = 12.0
var _time_progression: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_translations()
	_connect_view_signals()
	_apply_initial_view_state()

	# 시작 시 포즈 메뉴 숨김
	if pause_view:
		pause_view.visible = false

func _notification(what: int) -> void:
	if is_inside_tree() and get_tree().has_meta("custom_asset_debugger_open"):
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# 창이 포커스를 잃었을 때(Alt+Tab 등) 마우스 커서를 즉시 해제
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			# 포커스가 돌아왔을 때, 일시정지 중이거나 Alt 키를 누르고 있지 않다면 마우스 다시 캡처
			if not _is_paused and not _alt_held:
				# 클릭으로 게임에 복귀할 수 있도록 즉시 캡처
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _load_translations() -> void:
	var path := "res://assets/translations.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var res = JSON.parse_string(file.get_as_text())
		if typeof(res) == TYPE_DICTIONARY:
			_translations = res

func _connect_view_signals() -> void:
	if not pause_view:
		return

	if pause_view.has_signal("resume_requested"):
		pause_view.resume_requested.connect(_on_resume_requested)
	if pause_view.has_signal("main_menu_requested"):
		pause_view.main_menu_requested.connect(_on_main_menu_requested)
	if pause_view.has_signal("sensitivity_changed"):
		pause_view.sensitivity_changed.connect(_on_sensitivity_changed)
	if pause_view.has_signal("msaa_toggled"):
		pause_view.msaa_toggled.connect(_on_msaa_toggled)
	pause_view.fps_toggled.connect(_on_fps_toggled)
	if pause_view.has_signal("fog_toggled"):
		pause_view.fog_toggled.connect(_on_fog_toggled)
	if pause_view.has_signal("shadows_toggled"):
		pause_view.shadows_toggled.connect(_on_shadows_toggled)
	if pause_view.has_signal("flight_vector_toggled"):
		pause_view.flight_vector_toggled.connect(_on_flight_vector_toggled)
	if pause_view.has_signal("weather_toggled"):
		pause_view.weather_toggled.connect(_on_weather_toggled)
	if pause_view.has_signal("weather_state_changed"):
		pause_view.weather_state_changed.connect(_on_weather_state_changed)
	if pause_view.has_signal("cloud_quality_changed"):
		pause_view.cloud_quality_changed.connect(_on_cloud_quality_changed)
	if pause_view.has_signal("laptop_mode_requested"):
		pause_view.laptop_mode_requested.connect(_on_laptop_mode_requested)
	if pause_view.has_signal("time_changed"):
		pause_view.time_changed.connect(_on_time_changed)
	if pause_view.has_signal("time_progression_toggled"):
		pause_view.time_progression_toggled.connect(_on_time_progression_toggled)

	if day_night_service and day_night_service.has_signal("time_changed"):
		day_night_service.connect("time_changed", _on_service_time_changed)

func _apply_initial_view_state() -> void:
	var root = get_tree().root
	var lang: String = "ko"
	var settings = root.get_node_or_null("UserSettingsService")

	if settings:
		lang = settings.current_language
		_flight_vector_enabled = bool(settings.flight_vector_enabled)
		_weather_enabled = bool(settings.weather_enabled)
		_weather_state = int(settings.weather_state)
	elif root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc:
			lang = svc.current_language

	var dict: Dictionary = _translations.get(lang, {})
	if pause_view and pause_view.has_method("update_localization"):
		pause_view.update_localization(dict)

	var sens: float = 0.003
	if settings:
		sens = float(settings.mouse_sensitivity)
	elif player_node and "mouse_sensitivity" in player_node:
		sens = float(player_node.get("mouse_sensitivity"))

	if player_node:
		player_node.mouse_sensitivity = sens

	var msaa: bool = settings.msaa_enabled if settings else (get_viewport().msaa_3d != Viewport.MSAA_DISABLED)
	pause_view.fps_check.set_pressed_no_signal(settings.fps_display_enabled if settings else true)
	get_viewport().msaa_3d = Viewport.MSAA_2X if msaa else Viewport.MSAA_DISABLED

	var fog: bool = settings.fog_enabled if settings else true
	if world_environment and world_environment.environment:
		world_environment.environment.fog_enabled = fog

	var shadow: bool = settings.shadow_enabled if settings else true
	if sun_light:
		sun_light.shadow_enabled = shadow

	var cloud_q: int = settings.cloud_quality if settings else 1
	if weather_manager and weather_manager.has_method("set_cloud_quality"):
		weather_manager.call("set_cloud_quality", cloud_q)

	if settings and "time_hours" in settings:
		_time_hours = float(settings.get("time_hours"))
		_time_progression = bool(settings.get("time_progression"))
	if day_night_service:
		if day_night_service.has_method("set_time_hours"):
			day_night_service.call("set_time_hours", _time_hours)
		if day_night_service.has_method("set_time_progression"):
			day_night_service.call("set_time_progression", _time_progression)

	if pause_view and pause_view.has_method("set_initial_settings"):
		pause_view.set_initial_settings(sens, msaa, fog, shadow, _flight_vector_enabled, _weather_enabled, _weather_state, cloud_q, _time_hours, _time_progression)

	if flight_vector_hud and flight_vector_hud.has_method("set_hud_visible"):
		flight_vector_hud.set_hud_visible(_flight_vector_enabled)

	if weather_manager and weather_manager.has_method("set_weather_system_enabled"):
		weather_manager.set_weather_system_enabled(_weather_enabled)
	if weather_manager and weather_manager.has_method("apply_weather"):
		weather_manager.call("apply_weather", _weather_state)

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().has_meta("custom_asset_debugger_open"):
		return
	# 1. ESC 키 -> 일시정지 토글
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			toggle_pause()
			get_viewport().set_input_as_handled()
			return
		# 2. F1 키 -> 도움말 오버레이 토글
		elif event.keycode == KEY_F1:
			_toggle_help_overlay()
			get_viewport().set_input_as_handled()
			return
		# 3. [ / ] 키 -> 시간대 1시간 즉각 전진/후진 (시간 변경 및 낮밤 즉각 반영)
		elif event.keycode == KEY_BRACKETLEFT:
			_adjust_time_relative(-1.0)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_BRACKETRIGHT:
			_adjust_time_relative(1.0)
			get_viewport().set_input_as_handled()
			return

	# 2. ALT 키 한시적 마우스 릴리즈 (Hold ALT to release cursor)
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			if event.pressed and not _alt_held:
				_alt_held = true
				if not _is_paused:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			elif not event.pressed and _alt_held:
				_alt_held = false
				if not _is_paused:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func toggle_pause() -> void:
	_set_paused(!_is_paused)

func _set_paused(pause: bool) -> void:
	_is_paused = pause
	get_tree().paused = _is_paused

	if pause_view:
		pause_view.visible = _is_paused
		if _is_paused and pause_view.has_method("show_pause_menu"):
			pause_view.show_pause_menu()

	if _is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if _alt_held:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_requested() -> void:
	_set_paused(false)

func _on_main_menu_requested() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/ui/map_selection_menu.tscn")

func _on_sensitivity_changed(val: float) -> void:
	if player_node:
		player_node.mouse_sensitivity = val
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.mouse_sensitivity = val
		settings.save_settings()

func _on_msaa_toggled(enabled: bool) -> void:
	get_viewport().msaa_3d = Viewport.MSAA_2X if enabled else Viewport.MSAA_DISABLED
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.msaa_enabled = enabled
		settings.save_settings()

func _on_fps_toggled(enabled: bool) -> void:
	var settings := get_node("/root/UserSettingsService")
	settings.fps_display_enabled = enabled
	settings.save_settings()
	get_parent().get_node("PerformanceHUD").set_hud_visible(enabled)

func _on_fog_toggled(enabled: bool) -> void:
	if world_environment and world_environment.environment:
		world_environment.environment.fog_enabled = enabled
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.fog_enabled = enabled
		settings.save_settings()

func _on_shadows_toggled(enabled: bool) -> void:
	if sun_light:
		sun_light.shadow_enabled = enabled
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.shadow_enabled = enabled
		settings.save_settings()

func _on_flight_vector_toggled(enabled: bool) -> void:
	_flight_vector_enabled = enabled
	if flight_vector_hud and flight_vector_hud.has_method("set_hud_visible"):
		flight_vector_hud.set_hud_visible(enabled)
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.flight_vector_enabled = enabled
		settings.save_settings()
	print("[PauseSettingsController] Flight Vector HUD: ", "ENABLED" if enabled else "DISABLED")

func _on_weather_toggled(enabled: bool) -> void:
	_weather_enabled = enabled
	if weather_manager and weather_manager.has_method("set_weather_system_enabled"):
		weather_manager.set_weather_system_enabled(enabled)
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.weather_enabled = enabled
		settings.save_settings()
	print("[PauseSettingsController] Weather System: ", "ENABLED" if enabled else "DISABLED")

func _on_weather_state_changed(state_index: int) -> void:
	_weather_state = state_index
	if weather_manager and weather_manager.has_method("apply_weather"):
		weather_manager.call("apply_weather", state_index)
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.weather_state = state_index
		settings.save_settings()
	var state_names := ["CLEAR", "CIRRUS_FAIR", "PARTLY_CLOUDY", "OVERCAST", "FOGGY", "RAIN", "STORM"]
	var name_str: String = state_names[state_index] if state_index < state_names.size() else "UNKNOWN"
	print("[PauseSettingsController] Weather State -> ", name_str)

func _on_cloud_quality_changed(quality_index: int) -> void:
	if weather_manager and weather_manager.has_method("set_cloud_quality"):
		weather_manager.call("set_cloud_quality", quality_index)
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings:
		settings.cloud_quality = quality_index
		settings.save_settings()
	var quality_names := ["ULTRA", "HIGH", "MEDIUM", "LAPTOP_LOW", "OFF"]
	var q_str: String = quality_names[quality_index] if quality_index < quality_names.size() else "UNKNOWN"
	print("[PauseSettingsController] Cloud Quality Changed -> ", q_str)

func _on_laptop_mode_requested() -> void:
	print("[PauseSettingsController] Applying Laptop Preset (Cloud: Laptop/Low, Shadow: OFF, MSAA: OFF)...")
	# 1. 구름 품질 -> 노트북(3: Laptop/Low)
	_on_cloud_quality_changed(3)
	# 2. 그림자 비활성화
	_on_shadows_toggled(false)
	# 3. 안티앨리어싱 비활성화
	_on_msaa_toggled(false)
	# 4. 안개는 가시성 및 배경 차단을 위해 유지
	_on_fog_toggled(true)

func _toggle_help_overlay() -> void:
	if not help_overlay_hud:
		return
	# 현재 언어 감지
	var lang := "ko"
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc:
			lang = svc.current_language
	if help_overlay_hud.has_method("toggle_help"):
		help_overlay_hud.toggle_help(lang)

func _adjust_time_relative(delta_hours: float) -> void:
	if day_night_service and "current_time_hours" in day_night_service:
		var cur: float = float(day_night_service.get("current_time_hours"))
		var new_time: float = fmod(cur + delta_hours, 24.0)
		if new_time < 0.0:
			new_time += 24.0
		_on_time_changed(new_time)

func _on_time_changed(hours: float) -> void:
	_time_hours = hours
	if day_night_service and day_night_service.has_method("set_time_hours"):
		day_night_service.call("set_time_hours", hours)
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings and "time_hours" in settings:
		settings.set("time_hours", hours)
		settings.save_settings()

func _on_time_progression_toggled(enabled: bool) -> void:
	_time_progression = enabled
	if day_night_service and day_night_service.has_method("set_time_progression"):
		day_night_service.call("set_time_progression", enabled)
	var settings = get_tree().root.get_node_or_null("UserSettingsService")
	if settings and "time_progression" in settings:
		settings.set("time_progression", enabled)
		settings.save_settings()
	print("[PauseSettingsController] Time Progression: ", "ON" if enabled else "OFF")

func _on_service_time_changed(hours: float, _time_str: String) -> void:
	_time_hours = hours
	if pause_view and pause_view.has_method("update_time_display"):
		pause_view.call("update_time_display", hours)
