extends Node3D
class_name VesselWorldManager

const Route = preload("res://scripts/water/vessel_route.gd")
const ModelFactory = preload("res://scripts/water/vessel_model_factory.gd")
const Wake = preload("res://scripts/water/vessel_wake.gd")
const CATALOG = "res://assets/generated/vessels/traffic.json"

@export var player_node: Node3D
@export var auto_initialize: bool = true
var enabled: bool = true
var elapsed: float = 0.0
var _settings: Dictionary = {}
var _traffic: Array = []
var _models: Dictionary = {}
var _wakes: Dictionary = {}
var _factory = ModelFactory.new()

func _ready() -> void:
	set_process(false)
	if not auto_initialize:
		return
	var maps = get_node_or_null("/root/MapSelectionService")
	var preferences = get_node_or_null("/root/UserSettingsService")
	if maps and maps.selected_map:
		var data = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if data is Dictionary:
			configure(data, maps.selected_map.id, preferences)

func configure(catalog: Dictionary, map_id: String, preferences: Node = null) -> void:
	_clear_models()
	_traffic.clear()
	elapsed = 0.0
	_settings = catalog.get("settings", {})
	var map: Dictionary = catalog.get("maps", {}).get(map_id, {})
	for entry in map.get("entries", []):
		var route = Route.new()
		route.configure(entry, float(map.get("sea_level", 0.0)), _settings)
		_traffic.append({"entry":entry, "route":route})
	if preferences:
		if not preferences.vessels_enabled_changed.is_connected(set_enabled):
			preferences.vessels_enabled_changed.connect(set_enabled)
		set_enabled(preferences.vessels_enabled)
	else:
		set_enabled(true)

func set_enabled(value: bool) -> void:
	enabled = value
	set_process(enabled and not _traffic.is_empty())
	if enabled:
		_update_models(0.0)
	else:
		_clear_models()

func _process(delta: float) -> void:
	elapsed += delta * float(_settings.get("time_scale", 1.0))
	_update_models(delta)

func _update_models(delta: float) -> void:
	var range_m := float(_settings.get("render_distance_m", 14000.0))
	for item in _traffic:
		var entry: Dictionary = item.entry
		var pose: Transform3D = item.route.sample(elapsed)
		var id: String = entry.id
		if player_node and player_node.global_position.distance_to(pose.origin) > range_m:
			if _models.has(id):
				_models[id].visible = false
			if _wakes.has(id):
				_wakes[id].free()
				_wakes.erase(id)
			continue
		var vessel: Node3D = _models.get(id)
		if vessel == null:
			# 모델 준비 전에는 건너뛰고 다음 프레임에 다시 확인한다.
			vessel = _factory.instantiate(entry, false)
			if vessel == null:
				continue
			vessel.name = id
			add_child(vessel)
			vessel.transform = pose
			_models[id] = vessel
		if entry.get("mode", "sailing") != "moored" and bool(_settings.get("wake_enabled", true)):
			if not _wakes.has(id):
				var wake := Wake.new()
				wake.configure(entry, _settings)
				add_child(wake)
				_wakes[id] = wake
			var wake_pose := Transform3D(vessel.basis, pose.origin)
			_wakes[id].advance(delta, wake_pose, item.route.moving_speed(elapsed) * float(_settings.get("time_scale", 1.0)))
		vessel.visible = true
		vessel.position = pose.origin
		if delta > 0.0:
			var target := pose.basis.get_rotation_quaternion()
			var current := vessel.basis.get_rotation_quaternion()
			var angle := current.angle_to(target)
			vessel.basis = Basis(current.slerp(target, minf(1.0, delta * 0.12 / maxf(angle, 0.0001))))

func _exit_tree() -> void:
	_factory.dispose()

func _clear_models() -> void:
	for wake in _wakes.values():
		wake.free()
	_wakes.clear()
	for vessel in _models.values():
		vessel.free()
	_models.clear()
