extends Node3D
class_name WeatherManager

## 기후 상태 머신 및 통합 날씨 관리 오케스트레이터
## 7가지 현실적 기상 상태(맑음, 쾌청/권운, 부분흐림, 흐림/덮개구름, 안개, 비, 뇌우) 관리

enum WeatherType {
	CLEAR,          # 0: 쾌청 (구름 없음)
	CIRRUS_FAIR,    # 1: 맑음 (고고도 새털구름)
	PARTLY_CLOUDY,  # 2: 구름 조금 (저고도 뭉게구름)
	OVERCAST,       # 3: 흐림 (중고도 층적운 덮개)
	FOGGY,          # 4: 짙은 안개 (낮은 시정)
	RAIN,           # 5: 비 (층적운 + 적운 + 강우)
	STORM           # 6: 뇌우 (수직 거대 적란운 + 폭우 + 낙뢰)
}

@export var current_weather: WeatherType = WeatherType.PARTLY_CLOUDY
@export var player_node: Node3D
@export var world_environment: WorldEnvironment
@export var sun_light: DirectionalLight3D

# Node3D 기반으로 선언 후 has_method / call 로 동적 디스패치
@export var cloud_manager: Node3D
@export var rain_controller: Node3D
@export var lightning_controller: Node3D
@export var day_night_service: Node

var _weather_enabled: bool = true
var _base_fog_density: float = 0.000028

func _ready() -> void:
	call_deferred("apply_weather", current_weather)

func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 6 == 0:
		_apply_altitude_adjusted_fog()

func _apply_altitude_adjusted_fog() -> void:
	if not world_environment or not world_environment.environment:
		return
	var factor: float = 1.0
	if player_node:
		var alt: float = player_node.global_position.y
		if alt > 1000.0:
			# 1,000m ~ 15,000m 고도 상승에 따라 대기 밀도 감소 (최대 80% 희석, 최소 20% 잔존)
			factor = clampf(1.0 - (alt - 1000.0) / 17500.0, 0.20, 1.0)
	world_environment.environment.fog_density = _base_fog_density * factor

func set_weather_system_enabled(enabled: bool) -> void:
	_weather_enabled = enabled
	visible = enabled
	if cloud_manager and cloud_manager.has_method("set_clouds_enabled"):
		cloud_manager.call("set_clouds_enabled", enabled)
	if rain_controller and rain_controller.has_method("set_rain_enabled"):
		rain_controller.call("set_rain_enabled", enabled)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", enabled)
	if enabled:
		apply_weather(current_weather)

func is_weather_system_enabled() -> bool:
	return _weather_enabled

func set_cloud_quality(quality_level: int) -> void:
	if cloud_manager and cloud_manager.has_method("set_cloud_quality"):
		cloud_manager.call("set_cloud_quality", quality_level)

func apply_weather(type: WeatherType) -> void:
	current_weather = type
	print("[WeatherManager] apply_weather called with type: %d (enabled=%s)" % [type, _weather_enabled])
	if not _weather_enabled:
		return

	match type:
		WeatherType.CLEAR:
			_set_clear_weather()
		WeatherType.CIRRUS_FAIR:
			_set_cirrus_fair_weather()
		WeatherType.PARTLY_CLOUDY:
			_set_partly_cloudy_weather()
		WeatherType.OVERCAST:
			_set_overcast_weather()
		WeatherType.FOGGY:
			_set_foggy_weather()
		WeatherType.RAIN:
			_set_rain_weather()
		WeatherType.STORM:
			_set_storm_weather()

func _set_clear_weather() -> void:
	if cloud_manager and cloud_manager.has_method("set_clouds_enabled"):
		cloud_manager.call("set_clouds_enabled", true)
		cloud_manager.call("configure_composition", 0.0, 0.0, 0.0, 0.0,
			Color(0.98, 0.98, 1.0), Color(0.85, 0.88, 0.95), Color(0.40, 0.45, 0.55))
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 0.0)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", false)
	_update_environment(Color(0.68, 0.78, 0.88, 1.0), 0.000018, 1.25)

func _set_cirrus_fair_weather() -> void:
	# 고고도 권운만 80% 출현 (화창한 날 하늘)
	if cloud_manager:
		cloud_manager.call("set_clouds_enabled", true)
		if cloud_manager.has_method("configure_composition"):
			cloud_manager.call(
				"configure_composition", 0.0, 0.0, 0.8, 0.0,
				Color(0.98, 0.98, 1.0, 1.0), Color(0.85, 0.88, 0.95, 1.0), Color(0.40, 0.45, 0.55, 1.0)
			)
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 0.0)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", false)
	_update_environment(Color(0.65, 0.76, 0.86, 1.0), 0.000022, 1.2)

func _set_partly_cloudy_weather() -> void:
	# 저고도 적운 70% + 고고도 권운 40% 복합 합성 (일반적인 뭉게구름 날씨)
	if cloud_manager:
		cloud_manager.call("set_clouds_enabled", true)
		if cloud_manager.has_method("configure_composition"):
			cloud_manager.call(
				"configure_composition", 0.7, 0.2, 0.4, 0.0,
				Color(0.95, 0.96, 0.99, 1.0), Color(0.62, 0.67, 0.76, 1.0), Color(0.28, 0.32, 0.42, 1.0)
			)
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 0.0)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", false)
	_update_environment(Color(0.60, 0.68, 0.76, 1.0), 0.000028, 1.05)

func _set_overcast_weather() -> void:
	# 중고도 층적운 100% + 저고도 적운 40% (하늘을 두텁게 덮은 회색빛 날씨)
	if cloud_manager:
		cloud_manager.call("set_clouds_enabled", true)
		if cloud_manager.has_method("configure_composition"):
			cloud_manager.call(
				"configure_composition", 0.4, 1.0, 0.0, 0.0,
				Color(0.70, 0.73, 0.78, 1.0), Color(0.45, 0.48, 0.55, 1.0), Color(0.25, 0.27, 0.35, 1.0)
			)
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 0.0)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", false)
	_update_environment(Color(0.52, 0.56, 0.62, 1.0), 0.000055, 0.8)

func _set_foggy_weather() -> void:
	# 저고도 층적운 50% + 극심한 대기 안개 (짙은 해무 및 박무)
	if cloud_manager:
		cloud_manager.call("set_clouds_enabled", true)
		if cloud_manager.has_method("configure_composition"):
			cloud_manager.call(
				"configure_composition", 0.2, 0.6, 0.0, 0.0,
				Color(0.80, 0.82, 0.85, 1.0), Color(0.60, 0.63, 0.68, 1.0), Color(0.35, 0.38, 0.45, 1.0)
			)
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 0.0)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", false)
	_update_environment(Color(0.70, 0.73, 0.77, 1.0), 0.000150, 0.6)

func _set_rain_weather() -> void:
	# 층적운 90% + 적운 60% 어두운 비구름 + 빗줄기 70%
	if cloud_manager:
		cloud_manager.call("set_clouds_enabled", true)
		if cloud_manager.has_method("configure_composition"):
			cloud_manager.call(
				"configure_composition", 0.6, 0.9, 0.0, 0.2,
				Color(0.55, 0.58, 0.65, 1.0), Color(0.32, 0.35, 0.42, 1.0), Color(0.18, 0.20, 0.26, 1.0)
			)
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 0.75)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", false)
	_update_environment(Color(0.42, 0.46, 0.52, 1.0), 0.000070, 0.6)

func _set_storm_weather() -> void:
	# 거대 적란운 100% + 층적운 100% + 폭우 100% + 천둥 낙뢰
	if cloud_manager:
		cloud_manager.call("set_clouds_enabled", true)
		if cloud_manager.has_method("configure_composition"):
			cloud_manager.call(
				"configure_composition", 0.8, 1.0, 0.0, 1.0,
				Color(0.35, 0.38, 0.45, 1.0), Color(0.18, 0.20, 0.25, 1.0), Color(0.10, 0.12, 0.16, 1.0)
			)
	if rain_controller and rain_controller.has_method("set_rain_intensity"):
		rain_controller.call("set_rain_intensity", 1.0)
	if lightning_controller and lightning_controller.has_method("set_lightning_enabled"):
		lightning_controller.call("set_lightning_enabled", true)
	_update_environment(Color(0.28, 0.30, 0.35, 1.0), 0.000100, 0.35)

func _update_environment(fog_col: Color, fog_dens: float, sun_energy: float) -> void:
	_base_fog_density = fog_dens
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.fog_light_color = fog_col
		_apply_altitude_adjusted_fog()
	if day_night_service and day_night_service.has_method("set_weather_light_scale"):
		day_night_service.call("set_weather_light_scale", sun_energy)
	elif sun_light:
		sun_light.light_energy = sun_energy
