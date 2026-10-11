extends Node
class_name DayNightCycleService

## 태양 방위각/고도각, 주야간 광량, 대기광 및 시간대 변경 관리 서비스
## 시간의 연속적 흐름과 슬라이더/단축키를 통한 즉각적인 시간대 변경을 모두 지원

signal time_changed(time_hours: float, time_string: String)
signal cycle_speed_changed(speed_multiplier: float)

@export var sun_light: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var weather_manager: Node3D

# 시간 설정 (0.0 ~ 24.0 시간 단위)
@export_range(0.0, 24.0, 0.1) var current_time_hours: float = 12.0
@export var is_time_progression_active: bool = true
# 1.0 = 실시간(24시간=24시간), 60.0 = 1분이 인게임 1시간(24분=하루), 기본 120.0 (12분=하루)
@export var time_speed_multiplier: float = 120.0

# 기준 태양/환경 색상 및 파라미터 캐시
var _weather_light_energy_scale: float = 1.0
var _sky_material: ShaderMaterial
var _celestial_manager: Node
var _last_sky_night_bucket := -1

# 시간대별 프리셋 색상 (낮, 일출/일몰, 밤)
const NOON_SKY_TOP := Color(0.32, 0.52, 0.78, 1.0)
const NOON_SKY_HORIZON := Color(0.68, 0.75, 0.82, 1.0)
const NOON_GROUND_BOTTOM := Color(0.12, 0.15, 0.18, 1.0)
const NOON_GROUND_HORIZON := Color(0.68, 0.75, 0.82, 1.0)
const NOON_SUN_COLOR := Color(1.0, 0.98, 0.92, 1.0)
const NOON_AMBIENT := Color(0.35, 0.40, 0.45, 1.0)

const SUNSET_SKY_TOP := Color(0.18, 0.22, 0.45, 1.0)
const SUNSET_SKY_HORIZON := Color(0.85, 0.42, 0.20, 1.0)
const SUNSET_GROUND_BOTTOM := Color(0.08, 0.08, 0.10, 1.0)
const SUNSET_GROUND_HORIZON := Color(0.35, 0.20, 0.15, 1.0)
const SUNSET_SUN_COLOR := Color(1.0, 0.55, 0.25, 1.0)
const SUNSET_AMBIENT := Color(0.25, 0.18, 0.20, 1.0)

const NIGHT_SKY_TOP := Color(0.02, 0.03, 0.07, 1.0)
const NIGHT_SKY_HORIZON := Color(0.05, 0.06, 0.12, 1.0)
const NIGHT_GROUND_BOTTOM := Color(0.01, 0.01, 0.02, 1.0)
const NIGHT_GROUND_HORIZON := Color(0.03, 0.04, 0.06, 1.0)
const NIGHT_MOON_COLOR := Color(0.65, 0.72, 0.88, 1.0)
const NIGHT_AMBIENT := Color(0.06, 0.07, 0.10, 1.0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cache_sky_material()
	_celestial_manager = get_node_or_null("../CelestialBodyManager")
	set_time_hours(current_time_hours)

func _cache_sky_material() -> void:
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		if env.sky and env.sky.sky_material is ShaderMaterial:
			_sky_material = env.sky.sky_material as ShaderMaterial

func _process(delta: float) -> void:
	if is_time_progression_active and time_speed_multiplier > 0.0:
		# delta(초) * multiplier / 3600 -> 시간 단위 가산
		var delta_hours := (delta * time_speed_multiplier) / 3600.0
		var new_time := fmod(current_time_hours + delta_hours, 24.0)
		if new_time < 0.0:
			new_time += 24.0
		set_time_hours(new_time)

## 특정 시간대로 즉각 변경 (0.0 ~ 24.0)
func set_time_hours(hours: float) -> void:
	current_time_hours = clampf(hours, 0.0, 24.0)
	if current_time_hours >= 24.0:
		current_time_hours = 0.0
	_update_sun_and_environment()
	time_changed.emit(current_time_hours, get_formatted_time_string())

func set_time_progression(active: bool) -> void:
	is_time_progression_active = active

func set_time_speed_multiplier(multiplier: float) -> void:
	time_speed_multiplier = maxf(0.0, multiplier)
	cycle_speed_changed.emit(time_speed_multiplier)

func set_weather_light_scale(scale_val: float) -> void:
	_weather_light_energy_scale = clampf(scale_val, 0.1, 2.0)
	_update_sun_and_environment()

func get_formatted_time_string() -> String:
	var total_minutes := int(current_time_hours * 60.0)
	var hrs := (total_minutes / 60) % 24
	var mins := total_minutes % 60
	return "%02d:%02d" % [hrs, mins]

func _update_sun_and_environment() -> void:
	# 태양 고도각(Pitch) 및 방위각(Yaw) 산출
	# 06:00 = 일출 (고도 0도, 동쪽), 12:00 = 정오 (고도 90도/남중), 18:00 = 일몰 (고도 0도, 서쪽), 24:00/00:00 = 자정
	var time_ratio := current_time_hours / 24.0
	var sun_angle_rad := (current_time_hours - 6.0) / 12.0 * PI # 6시=0, 12시=PI/2, 18시=PI
	var sun_altitude_deg := sin(sun_angle_rad) * 90.0 # -90 ~ +90 도
	var sun_azimuth_deg := (current_time_hours - 6.0) * 15.0 # 동(0) -> 남(90) -> 서(180) -> 북(270)
	var celestial_direction := Vector3.ZERO
	if is_instance_valid(_celestial_manager):
		celestial_direction = _celestial_manager.get_sun_world_direction()
		sun_altitude_deg = rad_to_deg(asin(clampf(celestial_direction.y, -1.0, 1.0)))

	if sun_light:
		# 태양 광원의 방향 회전 (Pitch, Yaw)
		var pitch_rad := deg_to_rad(-sun_altitude_deg)
		var yaw_rad := deg_to_rad(sun_azimuth_deg)
		sun_light.rotation = Vector3(pitch_rad, yaw_rad, 0.0)
		if celestial_direction != Vector3.ZERO:
			var light_direction := celestial_direction
			if sun_altitude_deg <= 0.0:
				light_direction = _celestial_manager.get_moon_world_direction()
			var up_axis := Vector3.FORWARD if absf(light_direction.y) > 0.999 else Vector3.UP
			sun_light.look_at(sun_light.global_position - light_direction, up_axis)

	# 고도에 따른 주간(Day), 황혼(Twilight), 야간(Night) 가중치 계산
	var day_weight: float = clampf((sun_altitude_deg - 5.0) / 35.0, 0.0, 1.0)
	var sunset_weight: float = 0.0
	if sun_altitude_deg >= -12.0 and sun_altitude_deg <= 15.0:
		sunset_weight = 1.0 - absf((sun_altitude_deg - 0.0) / 14.0)
		sunset_weight = clampf(sunset_weight, 0.0, 1.0)
	var night_weight: float = clampf((-sun_altitude_deg - 2.0) / 20.0, 0.0, 1.0)

	# 광원 색상 및 에너지 계산
	var current_sun_color: Color
	var current_sun_energy: float
	var current_ambient: Color

	if sun_altitude_deg > 0.0:
		# 주간 및 황혼
		current_sun_color = SUNSET_SUN_COLOR.lerp(NOON_SUN_COLOR, day_weight)
		var base_energy := lerpf(0.4, 1.25, day_weight)
		current_sun_energy = base_energy * _weather_light_energy_scale
		current_ambient = SUNSET_AMBIENT.lerp(NOON_AMBIENT, day_weight)
	else:
		# 야간 (달빛 약광원 모드)
		current_sun_color = SUNSET_SUN_COLOR.lerp(NIGHT_MOON_COLOR, night_weight)
		var moon_energy := lerpf(0.24, 0.16, night_weight)
		current_sun_energy = moon_energy * _weather_light_energy_scale
		current_ambient = SUNSET_AMBIENT.lerp(Color(0.105, 0.12, 0.17, 1.0), night_weight)

	if sun_light:
		sun_light.light_color = current_sun_color
		sun_light.light_energy = current_sun_energy
		# 밤에는 그림자 해상도 부하 감소 및 부드러운 달빛 표현
		sun_light.shadow_opacity = lerpf(0.4, 1.0, day_weight)

	# 하늘 및 대기 산란 색상 보간
	if _sky_material:
		var current_top: Color
		var current_horizon: Color
		var current_ground: Color

		if sun_altitude_deg > 0.0:
			current_top = SUNSET_SKY_TOP.lerp(NOON_SKY_TOP, day_weight)
			current_horizon = SUNSET_SKY_HORIZON.lerp(NOON_SKY_HORIZON, day_weight)
			current_ground = SUNSET_GROUND_BOTTOM.lerp(NOON_GROUND_BOTTOM, day_weight)
		else:
			current_top = SUNSET_SKY_TOP.lerp(NIGHT_SKY_TOP, night_weight)
			current_horizon = SUNSET_SKY_HORIZON.lerp(NIGHT_SKY_HORIZON, night_weight)
			current_ground = SUNSET_GROUND_BOTTOM.lerp(NIGHT_GROUND_BOTTOM, night_weight)

		_sky_material.set_shader_parameter("sky_top_color", current_top)
		_sky_material.set_shader_parameter("sky_horizon_color", current_horizon)
		_sky_material.set_shader_parameter("ground_color", current_ground)
		var night_bucket := int(round(night_weight * 100.0))
		if night_bucket != _last_sky_night_bucket:
			_sky_material.set_shader_parameter("night_weight", night_weight)
			_last_sky_night_bucket = night_bucket

	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.ambient_light_color = current_ambient
		env.ambient_light_energy = lerpf(0.8, 0.72, night_weight)
		# 야간에는 안개 색상도 어둡게 동기화
		var target_fog := Color(0.65, 0.72, 0.80, 1.0).lerp(Color(0.04, 0.05, 0.09, 1.0), night_weight)
		if sunset_weight > 0.0:
			target_fog = target_fog.lerp(Color(0.60, 0.35, 0.25, 1.0), sunset_weight * 0.7)
		env.fog_light_color = target_fog
	if is_instance_valid(_celestial_manager) and _celestial_manager.has_method("set_night_weight"):
		_celestial_manager.call("set_night_weight", night_weight)
