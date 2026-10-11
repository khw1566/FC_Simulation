extends Node3D
## 독립 씬 선택용. 대량 배치는 카탈로그의 GLB로 MultiMesh를 구성한다.
@export var near_end_m: float = 350.0
@export var far_begin_m: float = 1200.0
@export var cull_m: float = 10000.0
@export var hysteresis_ratio: float = 0.05
var _elapsed: float = 0.0
var _level: int = -1
var _particle_defaults: Dictionary = {}

func _ready() -> void:
	_capture_particles($Near)
	_update_camera()

func _capture_particles(node: Node) -> void:
	if node is GPUParticles3D or node is CPUParticles3D:
		_particle_defaults[node.get_instance_id()] = node.emitting
	for child in node.get_children():
		_capture_particles(child)

func _toggle_particles(node: Node, active: bool) -> void:
	if node is GPUParticles3D or node is CPUParticles3D:
		node.emitting = active and bool(_particle_defaults.get(node.get_instance_id(), false))
	for child in node.get_children():
		_toggle_particles(child, active)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		_update_camera()

func _update_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		set_distance(camera.global_position.distance_to(global_position))

func set_distance(distance_m: float) -> void:
	var previous: int = _level
	var thresholds: Array[float] = [near_end_m, far_begin_m, cull_m]
	if _level < 0:
		_level = 0
		while _level < 3 and distance_m >= thresholds[_level]:
			_level += 1
	else:
		while _level < 3 and distance_m > thresholds[_level] * (1.0 + hysteresis_ratio):
			_level += 1
		while _level > 0 and distance_m < thresholds[_level - 1] * (1.0 - hysteresis_ratio):
			_level -= 1
	$Near.visible = _level == 0
	$Far.visible = _level == 1
	$VeryFar.visible = _level == 2
	if previous != _level:
		$Near.process_mode = Node.PROCESS_MODE_INHERIT if _level == 0 else Node.PROCESS_MODE_DISABLED
		_toggle_particles($Near, _level == 0)
