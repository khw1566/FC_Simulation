extends Node3D
## 고정 풀의 기상 혼합·바람·품질 예산을 관리한다.
const Factory = preload("res://scripts/weather/cloud_pool_factory.gd")
const LIMITS = [[6, 4, 4, 2], [5, 3, 3, 1], [3, 2, 2, 1], [2, 1, 2, 0], [0, 0, 0, 0]]
@export var player_node: Node3D
@export var day_night_service: Node
@export var spawn_radius := 6500.0
@export var wind_velocity := Vector3(8.0, 0.0, 4.0)
@export var transition_seconds := 12.0
var _pool: Array[Dictionary] = []
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
var _tick := 0.0
var _previous := Vector3.ZERO

func _ready() -> void:
	_pool = Factory.create(self, spawn_radius)
	if not day_night_service:
		day_night_service = get_node_or_null("../DayNightCycleService")
	for entry in _pool:
		entry.material.set_shader_parameter("night_weight", _get_night_weight())
		entry.material.set_shader_parameter("moonlight_scale", lerpf(1.0, 0.42, _get_night_weight()))
	if is_instance_valid(player_node):
		_previous = player_node.global_position
		for entry in _pool:
			entry.node.position += Vector3(_previous.x, 0, _previous.z)
	_refresh_enabled()

func _process(delta: float) -> void:
	var blend := 1.0 - exp(-delta * 3.0 / maxf(transition_seconds, 0.1))
	_ratios = _ratios.lerp(_target, blend)
	_top = _top.lerp(_target_top, blend)
	_bottom = _bottom.lerp(_target_bottom, blend)
	_shadow = _shadow.lerp(_target_shadow, blend)
	if _target == Vector4.ZERO and _ratios.length_squared() < 0.000001:
		for entry in _pool:
			entry.node.visible = false
		set_process(false)
		return
	var center := Vector3.ZERO
	if is_instance_valid(player_node):
		center = player_node.global_position
	_tick += delta
	for entry in _pool:
		var node: MeshInstance3D = entry.node
		node.position += wind_velocity * delta * (1.8 if entry.kind == 2 else 1.0)
		node.position.x = center.x + fposmod(node.position.x - center.x + spawn_radius, 2.0 * spawn_radius) - spawn_radius
		node.position.z = center.z + fposmod(node.position.z - center.z + spawn_radius, 2.0 * spawn_radius) - spawn_radius
	if _tick < 0.1:
		return
	var speed := center.distance_to(_previous) / maxf(_tick, 0.001)
	var night_weight := _get_night_weight()
	_previous = center
	_tick = 0.0
	for entry in _pool:
		var node: MeshInstance3D = entry.node
		var material: ShaderMaterial = entry.material
		var kind: int = entry.kind
		var limit: int = LIMITS[_current_quality][kind]
		var ratio: float = _ratios[kind]
		var weight := smoothstep(0.0, 1.0, clampf(ratio * float(limit) - float(entry.index), 0.0, 1.0))
		var offset := node.position - center
		var edge := maxf(absf(offset.x), absf(offset.z)) / spawn_radius
		weight *= 1.0 - smoothstep(0.70, 0.98, edge)
		node.visible = entry.index < limit and weight > 0.001
		if not node.visible:
			continue
		material.set_shader_parameter("opacity", weight)
		material.set_shader_parameter("coverage", lerpf(0.40, 0.90, ratio))
		material.set_shader_parameter("cloud_top_color", _top)
		material.set_shader_parameter("cloud_bottom_color", _bottom)
		material.set_shader_parameter("cloud_shadow_color", _shadow)
		var local := node.to_local(center)
		var nearby := absf(local.x) < 0.5 and absf(local.y) < 0.5 and absf(local.z) < 0.5
		var wake := clampf(speed / 150.0, 0.0, 0.8) if nearby and speed < 5000.0 and _current_quality < 3 else 0.0
		material.set_shader_parameter("player_pos_obj", local)
		material.set_shader_parameter("player_wake_strength", wake)
		material.set_shader_parameter("night_weight", night_weight)
		material.set_shader_parameter("moonlight_scale", lerpf(1.0, 0.42, night_weight))

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

func set_cloud_quality(level: int) -> void:
	_current_quality = clampi(level, 0, 4)
	for entry in _pool:
		entry.material.set_shader_parameter("quality_mode", _current_quality)
		if entry.index >= LIMITS[_current_quality][entry.kind]:
			entry.node.visible = false
	_refresh_enabled()

func set_clouds_enabled(enabled: bool) -> void:
	_is_active = enabled
	_refresh_enabled()

func _refresh_enabled() -> void:
	visible = _is_active and _current_quality < 4
	set_process(visible)
	if is_instance_valid(player_node):
		_previous = player_node.global_position
	_tick = 0.1
