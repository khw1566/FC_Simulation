extends Node

## 게임 전역 설정(비행 가속도, 그래픽, 오디오, 조작 민감도 등) 영구 저장 관리 서비스
## user://settings.cfg 파일을 통해 게임 재시작 후에도 설정 유지

const SETTINGS_FILE_PATH: String = "user://settings.cfg"

# 설정 기본값
var flight_accel_step: int = 2 # 기본 3단계 (60% 최고속도 비례)
var flight_gear: int = 1
var mouse_sensitivity: float = 0.003
var is_gravity_enabled: bool = false
var is_collision_enabled: bool = true
var msaa_enabled: bool = true
var fps_display_enabled: bool = true
var fog_enabled: bool = true
var shadow_enabled: bool = true
var flight_vector_enabled: bool = true
var weather_enabled: bool = true
var weather_state: int = 2
var cloud_quality: int = 1
var time_hours: float = 12.0
var time_progression: bool = true
var current_language: String = "ko"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	if err != OK:
		# 파일이 없으면 기본값으로 저장 생성
		save_settings()
		return

	flight_accel_step = config.get_value("flight", "accel_step", 2)
	flight_gear = config.get_value("flight", "flight_gear", 1)
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", 0.003)
	is_gravity_enabled = config.get_value("flight", "gravity_enabled", false)
	is_collision_enabled = config.get_value("flight", "collision_enabled", true)
	
	msaa_enabled = config.get_value("graphics", "msaa_enabled", true)
	fps_display_enabled = config.get_value("graphics", "fps_display_enabled", true)
	fog_enabled = config.get_value("graphics", "fog_enabled", true)
	shadow_enabled = config.get_value("graphics", "shadow_enabled", true)
	cloud_quality = config.get_value("graphics", "cloud_quality", 1)
	
	flight_vector_enabled = config.get_value("gameplay", "flight_vector_enabled", true)
	weather_enabled = config.get_value("gameplay", "weather_enabled", true)
	weather_state = config.get_value("gameplay", "weather_state", 2)
	time_hours = config.get_value("gameplay", "time_hours", 12.0)
	time_progression = config.get_value("gameplay", "time_progression", true)
	current_language = config.get_value("general", "language", "ko")
	print("[UserSettingsService] Loaded settings. Accel step: %d (60%% default)" % [flight_accel_step])

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("flight", "accel_step", flight_accel_step)
	config.set_value("flight", "flight_gear", flight_gear)
	config.set_value("flight", "gravity_enabled", is_gravity_enabled)
	config.set_value("flight", "collision_enabled", is_collision_enabled)

	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)

	config.set_value("graphics", "msaa_enabled", msaa_enabled)
	config.set_value("graphics", "fps_display_enabled", fps_display_enabled)
	config.set_value("graphics", "fog_enabled", fog_enabled)
	config.set_value("graphics", "shadow_enabled", shadow_enabled)
	config.set_value("graphics", "cloud_quality", cloud_quality)

	config.set_value("gameplay", "flight_vector_enabled", flight_vector_enabled)
	config.set_value("gameplay", "weather_enabled", weather_enabled)
	config.set_value("gameplay", "weather_state", weather_state)
	config.set_value("gameplay", "time_hours", time_hours)
	config.set_value("gameplay", "time_progression", time_progression)

	config.set_value("general", "language", current_language)

	var err := config.save(SETTINGS_FILE_PATH)
	if err == OK:
		print("[UserSettingsService] Saved settings to ", SETTINGS_FILE_PATH)
	else:
		push_error("[UserSettingsService] Failed to save settings. Error code: %d" % [err])
