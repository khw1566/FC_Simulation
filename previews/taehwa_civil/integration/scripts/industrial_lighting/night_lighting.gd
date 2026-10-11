extends Node3D
## 신호에 따라 주야간을 전환하고 인스턴스별 광량만 수정한다.

@export var automatic_time := true
@export_range(0.0, 1.0) var night_factor := 1.0
@export_range(0.0, 3.0) var brightness := 1.0
@export var local_lights_enabled := true
@export var day_night_service: Node

var _lights: Array[Light3D] = []
var _energies: Array[float] = []
var _materials: Array[Material] = []
var _last_factor := -1.0
var _celestial_service: Node

func _ready() -> void:
	var copies := {}
	for child in get_children():
		if child is Light3D:
			_lights.append(child)
			_energies.append(child.light_energy)
		elif child is MeshInstance3D:
			var material: Material = child.mesh.surface_get_material(0)
			if not copies.has(material):
				copies[material] = material.duplicate()
				_materials.append(copies[material])
			child.material_override = copies[material]
	_apply(night_factor)
	call_deferred("_bind_clock")

func _bind_clock() -> void:
	if not automatic_time:
		return
	if not day_night_service and get_tree().current_scene:
		day_night_service = get_tree().current_scene.find_child("DayNightCycleService", true, false)
	if day_night_service and day_night_service.has_signal("time_changed"):
		_celestial_service = day_night_service.get_node_or_null("../CelestialBodyManager")
		if not day_night_service.is_connected("time_changed", _clock_changed):
			day_night_service.connect("time_changed", _clock_changed)
		_clock_changed(float(day_night_service.get("current_time_hours")), "")

func _clock_changed(hours: float, _label: String) -> void:
	if not automatic_time:
		return
	var sun_height := sin((hours - 6.0) * PI / 12.0)
	# 태양 광원은 밤에 달빛 방향으로 재사용되므로 광원 회전으로 판정하지 않는다.
	if is_instance_valid(_celestial_service) and _celestial_service.has_method("get_sun_world_direction"):
		var sun_direction: Vector3 = _celestial_service.call("get_sun_world_direction")
		sun_height = sun_direction.y
	var factor := roundf((1.0 - smoothstep(-0.08, 0.12, sun_height)) * 40.0) / 40.0
	if factor != _last_factor:
		_apply(factor)

func set_night_factor(value: float) -> void:
	automatic_time = false
	night_factor = clampf(value, 0.0, 1.0)
	_apply(night_factor)

func apply_settings() -> void:
	_last_factor = -1.0
	if automatic_time and not day_night_service:
		_bind_clock()
	if automatic_time and day_night_service:
		_clock_changed(float(day_night_service.get("current_time_hours")), "")
	else:
		_apply(night_factor)

func _apply(factor: float) -> void:
	night_factor = factor
	_last_factor = factor
	visible = factor > 0.0 and brightness > 0.0
	for i in range(_lights.size()):
		_lights[i].visible = visible and local_lights_enabled
		_lights[i].light_energy = _energies[i] * factor * brightness
	for material in _materials:
		if material is StandardMaterial3D:
			material.emission_energy_multiplier = 2.5 * factor * brightness
		elif material is ShaderMaterial:
			material.set_shader_parameter("strength", 0.55 * factor * brightness)
