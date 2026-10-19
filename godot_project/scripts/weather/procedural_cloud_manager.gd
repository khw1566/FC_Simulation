extends Node3D
const OpticalEffects = preload("res://scripts/weather/optical_effects_controller.gd")
## 화면 1패스 구름층의 기상 혼합·고도풍 이동·태양광·품질 예산을 관리한다.
## 구름은 월드 좌표에 고정되어 지평선(최대 70km)까지 이어지고, 바람에 따라 흘러간다.

const Factory = preload("res://scripts/weather/cloud_layer_factory.gd")
const AtmosphereStateModelClass = preload("res://scripts/models/atmosphere_state_model.gd")
const SurfaceClimateModelClass = preload("res://scripts/models/surface_climate_model.gd")

# 품질 단계별 [주 표본 수, 태양광 표본 수, 세부 침식 거리 m, 태양광 계산 거리 m, 최대 거리 m]
const QUALITY := [
	[48, 3, 9000.0, 30000.0, 75000.0],
	[32, 2, 5000.0, 22000.0, 70000.0],
	[22, 1, 2000.0, 12000.0, 60000.0],
	[14, 0, 0.0, 0.0, 45000.0],
]
const LOW_WIND_ALTITUDE := 1800.0
const HIGH_WIND_ALTITUDE := 9000.0

@export var player_node: Node3D
@export var day_night_service: Node
@export var wind_velocity := Vector3(8.0, 0.0, 4.0) # 날씨 관리자가 없을 때의 대체 바람
@export var transition_seconds := 12.0

var _layer: MeshInstance3D
var _material: ShaderMaterial
var _weather_manager: Node
var _current_quality := 1
var _is_active := true
var _ratios := Vector4.ZERO
var _target := Vector4.ZERO
var _top := Color(0.96, 0.97, 1.0)
var _bottom := Color(0.60, 0.65, 0.73)
var _shadow := Color(0.30, 0.32, 0.38)
var _target_top := _top
var _target_bottom := _bottom
var _target_shadow := _shadow
var _wind_low := Vector3.ZERO
var _wind_high := Vector3.ZERO
var _target_wind_low := Vector3.ZERO
var _target_wind_high := Vector3.ZERO
var _offset_low := Vector2.ZERO
var _offset_high := Vector2.ZERO
var _evolve := 0.0
var _sync_timer := 0.0
# 3차원 바람장(WeatherManager/WindField). 없으면 대기 상태 모델의 두 고도 바람을 쓴다.
var _wind_field: Node
# 핵폭발이 있을 때만 켜는 뒤쪽 구간 구름 패스(버섯구름보다 먼 구름)
var _behind_layer: MeshInstance3D
var _behind_material: ShaderMaterial
var _uniform_names := PackedStringArray()

func _ready() -> void:
	var built := Factory.create(self)
	_layer = built.node
	_material = built.material
	var behind := Factory.create_behind(self, built)
	_behind_layer = behind.node
	_behind_material = behind.material
	for entry in _material.shader.get_shader_uniform_list():
		if str(entry.name) != "blast_split_mode":
			_uniform_names.append(str(entry.name))
	_weather_manager = get_parent()
	_wind_field = get_node_or_null("../WindField")
	if not day_night_service:
		day_night_service = get_node_or_null("../../DayNightCycleService")
	_target_wind_low = wind_velocity
	_target_wind_high = wind_velocity * 2.5
	_wind_low = _target_wind_low
	_wind_high = _target_wind_high
	_apply_quality()
	_sync_environment()
	_refresh_enabled()
	var optics := OpticalEffects.new()
	optics.name = "OpticalEffects"
	add_child(optics)

func _process(delta: float) -> void:
	var blend := 1.0 - exp(-delta * 3.0 / maxf(transition_seconds, 0.1))
	_ratios = _ratios.lerp(_target, blend)
	_top = _top.lerp(_target_top, blend)
	_bottom = _bottom.lerp(_target_bottom, blend)
	_shadow = _shadow.lerp(_target_shadow, blend)
	if _target == Vector4.ZERO and _ratios.length_squared() < 0.000001:
		_layer.visible = false
		_behind_layer.visible = false
		set_process(false)
		return
	_layer.visible = true

	_sync_timer += delta
	if _sync_timer >= 0.5:
		_sync_timer = 0.0
		_sync_environment()
	var wind_blend := 1.0 - exp(-delta * 0.5)
	_wind_low = _wind_low.lerp(_target_wind_low, wind_blend)
	_wind_high = _wind_high.lerp(_target_wind_high, wind_blend)
	# 셰이더는 (위치 + 이동량)을 표본하므로 바람 반대 방향으로 누적한다.
	_offset_low -= Vector2(_wind_low.x, _wind_low.z) * delta
	_offset_high -= Vector2(_wind_high.x, _wind_high.z) * delta
	_evolve += delta * 0.000012
	_material.set_shader_parameter("wind_offset", _offset_low)
	_material.set_shader_parameter("cirrus_offset", _offset_high)
	_material.set_shader_parameter("evolve", _evolve)
	var high_dir := Vector2(_wind_high.x, _wind_high.z)
	if high_dir.length_squared() > 0.01:
		_material.set_shader_parameter("cirrus_wind_dir", high_dir.normalized())
	_apply_wind_field()
	_apply_composition()
	_sync_behind_pass()

## 핵폭발이 있으면 구름층을 버섯구름 앞·뒤 두 구간 패스로 나눈다. 뒤쪽 패스에 같은 유니폼을 복사한다.
func _sync_behind_pass() -> void:
	var count = _material.get_shader_parameter("blast_count")
	var split := count != null and int(count) > 0 and _layer.visible
	_material.set_shader_parameter("blast_split_mode", 2 if split else 0)
	_behind_layer.visible = split
	if not split:
		return
	for key in _uniform_names:
		_behind_material.set_shader_parameter(key, _material.get_shader_parameter(key))

## 바람장 격자 텍스처와 층 평균 바람을 전달한다. 밀도장은 그 차이(국지 편차)만큼 구름을 밀어낸다.
func _apply_wind_field() -> void:
	if not _wind_field or not _wind_field.has_method("shader_state"):
		return
	var state: Dictionary = _wind_field.shader_state()
	for key in state:
		_material.set_shader_parameter(key, state[key])
	_material.set_shader_parameter("wind_layer_low", _wind_low)
	_material.set_shader_parameter("wind_layer_high", _wind_high)

## 기상 비율을 유형별 덮임·고도로 변환한다. 비·뇌우일수록 층운 밑면이 낮고 두꺼워진다.
func _apply_composition() -> void:
	var cu := _ratios.x * 0.75
	var st := _ratios.y
	var cb := _ratios.w
	# 뇌우 모루에서 흘러나온 권운, 비·흐림 때 중층 고층운을 함께 띄운다.
	var ci := maxf(_ratios.z, cb * 0.5)
	var alto := maxf(cb * 0.7, _ratios.y * 0.3)
	var st_base := 900.0 - 300.0 * cb
	var st_top := 2000.0 + 600.0 * cb
	var bottom := 1.0e9
	var top := -1.0e9
	if cu > 0.001:
		bottom = minf(bottom, 1100.0)
		top = maxf(top, 2700.0)
	if st > 0.001:
		bottom = minf(bottom, st_base)
		top = maxf(top, st_top)
	if alto > 0.001:
		bottom = minf(bottom, 4200.0)
		top = maxf(top, 5300.0)
	if cb > 0.001:
		bottom = minf(bottom, 650.0)
		top = maxf(top, 11800.0)
	if top < bottom:
		bottom = 0.0
		top = 0.0
	_material.set_shader_parameter("cu_coverage", cu)
	_material.set_shader_parameter("st_coverage", st)
	_material.set_shader_parameter("st_base", st_base)
	_material.set_shader_parameter("st_top", st_top)
	_material.set_shader_parameter("cb_coverage", cb)
	_material.set_shader_parameter("ci_coverage", ci)
	_material.set_shader_parameter("as_coverage", alto)
	_material.set_shader_parameter("slab_bottom", bottom)
	_material.set_shader_parameter("slab_top", top)
	_material.set_shader_parameter("cloud_top_color", _top)
	_material.set_shader_parameter("cloud_bottom_color", _bottom)
	_material.set_shader_parameter("cloud_shadow_color", _shadow)

## 태양(야간에는 달) 방향·색, 대기 안개, 고도풍을 0.5초마다 동기화한다.
func _sync_environment() -> void:
	var night := _get_night_weight()
	_material.set_shader_parameter("ambient_scale", lerpf(1.0, 0.12, night))
	var sun = _weather_manager.get("sun_light") if _weather_manager else null
	if sun is DirectionalLight3D:
		var light: DirectionalLight3D = sun
		_material.set_shader_parameter("sun_direction", light.global_transform.basis.z.normalized())
		var c := light.light_color * minf(light.light_energy, 2.0) if light.visible else Color.BLACK
		_material.set_shader_parameter("sun_color", Vector3(c.r, c.g, c.b))
	var world_env = _weather_manager.get("world_environment") if _weather_manager else null
	if world_env is WorldEnvironment and world_env.environment:
		var env: Environment = world_env.environment
		var fog := env.fog_light_color
		_material.set_shader_parameter("haze_color", Vector3(fog.r, fog.g, fog.b))
		_material.set_shader_parameter("haze_density", env.fog_density if env.fog_enabled else 0.0)
	if _wind_field and _wind_field.has_method("is_field_ready") and _wind_field.is_field_ready():
		# 구름층 전체 이동은 관측자 부근의 바람장 수평 성분을 따른다(지역에 따라 풍향이 달라진다).
		var here := _wind_anchor()
		var low_v: Vector3 = _wind_field.sample(Vector3(here.x, LOW_WIND_ALTITUDE, here.z))
		var high_v: Vector3 = _wind_field.sample(Vector3(here.x, HIGH_WIND_ALTITUDE, here.z))
		_target_wind_low = Vector3(low_v.x, 0.0, low_v.z)
		_target_wind_high = Vector3(high_v.x, 0.0, high_v.z)
	elif _weather_manager and "current_weather" in _weather_manager:
		var weather_type := int(_weather_manager.get("current_weather"))
		var hour: float = SurfaceClimateModelClass.resolve_hour(_weather_manager)
		var low = AtmosphereStateModelClass.calculate_at_altitude(LOW_WIND_ALTITUDE, 0.0, weather_type, hour)
		var high = AtmosphereStateModelClass.calculate_at_altitude(HIGH_WIND_ALTITUDE, 0.0, weather_type, hour)
		_target_wind_low = low.wind_vector
		_target_wind_high = high.wind_vector

func _get_night_weight() -> float:
	if not day_night_service or not ("current_time_hours" in day_night_service):
		return 0.0
	var hours := float(day_night_service.current_time_hours)
	var daylight := smoothstep(5.2, 7.8, hours) * (1.0 - smoothstep(17.0, 19.4, hours))
	return 1.0 - daylight

func configure_composition(cumulus_ratio: float, strato_ratio: float, cirrus_ratio: float, cb_ratio: float, top: Color, bottom: Color, shadow: Color) -> void:
	_target = Vector4(clampf(cumulus_ratio, 0, 1), clampf(strato_ratio, 0, 1), clampf(cirrus_ratio, 0, 1), clampf(cb_ratio, 0, 1))
	_target_top = top
	_target_bottom = bottom
	_target_shadow = shadow
	_refresh_enabled()

## 핵폭발 상호작용 유니폼(blast_*)을 구름층에 전달한다. 광학 패스는 SHARED 복사로 함께 받는다.
func set_blast_uniforms(values: Dictionary) -> void:
	if not _material:
		return
	for key in values:
		_material.set_shader_parameter(key, values[key])

func _wind_anchor() -> Vector3:
	return player_node.global_position if player_node else Vector3.ZERO

func get_cloud_quality() -> int:
	return _current_quality

## 고도별 바람(m/s): 저층(1.8km)과 고층(9km) 바람 사이를 보간한다.
func sample_wind(altitude: float) -> Vector3:
	if _wind_field and _wind_field.has_method("sample"):
		var here := _wind_anchor()
		return _wind_field.sample(Vector3(here.x, altitude, here.z))
	var k := clampf((altitude - LOW_WIND_ALTITUDE) / (HIGH_WIND_ALTITUDE - LOW_WIND_ALTITUDE), 0.0, 1.0)
	return _wind_low.lerp(_wind_high, k)

## 현재 보이는 저·중층 구름 덮개: [Vector3(중간 고도, 반두께, 덮임)] (응결 고리 배치용)
func get_cloud_decks() -> Array:
	var decks: Array = []
	if not _material or not _layer or not _layer.visible:
		return decks
	var cu := float(_material.get_shader_parameter("cu_coverage"))
	var st := float(_material.get_shader_parameter("st_coverage"))
	var alto := float(_material.get_shader_parameter("as_coverage"))
	if cu > 0.02 or st > 0.02:
		var lo := 1100.0 if cu >= st else float(_material.get_shader_parameter("st_base"))
		var hi := 2700.0 if cu >= st else float(_material.get_shader_parameter("st_top"))
		decks.append(Vector3((lo + hi) * 0.5, (hi - lo) * 0.35, maxf(cu, st)))
	if alto > 0.02:
		decks.append(Vector3(4750.0, 400.0, alto))
	return decks

func set_cloud_quality(level: int) -> void:
	_current_quality = clampi(level, 0, 4)
	_apply_quality()
	_refresh_enabled()

func set_clouds_enabled(enabled: bool) -> void:
	_is_active = enabled
	_refresh_enabled()

func _apply_quality() -> void:
	if not _material or _current_quality >= QUALITY.size():
		return
	var q: Array = QUALITY[_current_quality]
	_material.set_shader_parameter("step_count", int(q[0]))
	_material.set_shader_parameter("light_steps", int(q[1]))
	_material.set_shader_parameter("detail_distance", float(q[2]))
	_material.set_shader_parameter("light_distance", float(q[3]))
	_material.set_shader_parameter("max_distance", float(q[4]))

func _refresh_enabled() -> void:
	visible = _is_active and _current_quality < 4
	set_process(visible)
	if _layer and not visible:
		_layer.visible = false
		_behind_layer.visible = false
