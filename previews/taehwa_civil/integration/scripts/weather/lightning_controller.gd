extends Node3D
class_name LightningController

## 천둥 및 낙뢰 시뮬레이션 제어기 (절차적 번개 줄기, 환경광 섬광, 음속 지연 오디오 계산)

@export var player_node: Node3D
@export var sun_light: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var min_strike_interval: float = 6.0
@export var max_strike_interval: float = 14.0

var _is_active: bool = true
var _timer: float = 5.0
var _original_light_energy: float = 1.0
var _flash_timer: float = 0.0
var _bolt_mesh_instance: MeshInstance3D

func _ready() -> void:
	if sun_light:
		_original_light_energy = sun_light.light_energy
	_create_bolt_mesh_holder()
	_reset_timer()

func _create_bolt_mesh_holder() -> void:
	_bolt_mesh_instance = MeshInstance3D.new()
	_bolt_mesh_instance.name = "LightningBoltMesh"
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.95, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.9, 1.0)
	mat.emission_energy_multiplier = 4.0
	_bolt_mesh_instance.material_override = mat
	add_child(_bolt_mesh_instance)

func _reset_timer() -> void:
	_timer = randf_range(min_strike_interval, max_strike_interval)

func _process(delta: float) -> void:
	if not _is_active:
		return

	# 번개 섬광 감쇄 처리
	if _flash_timer > 0.0:
		_flash_timer -= delta
		var ratio := clampf(_flash_timer / 0.18, 0.0, 1.0)
		if sun_light:
			sun_light.light_energy = lerpf(_original_light_energy, _original_light_energy * 6.0, ratio)
		if ratio <= 0.05 and _bolt_mesh_instance:
			_bolt_mesh_instance.mesh = null
	else:
		if sun_light and sun_light.light_energy != _original_light_energy:
			sun_light.light_energy = _original_light_energy

	# 낙뢰 주기 타이머
	_timer -= delta
	if _timer <= 0.0:
		_trigger_lightning_strike()
		_reset_timer()

func _trigger_lightning_strike() -> void:
	var center_pos := Vector3.ZERO
	if player_node:
		center_pos = player_node.global_position

	# 플레이어 기준 반경 400m ~ 1800m 내 낙뢰 지점 산출
	var ang := randf_range(0.0, TAU)
	var dist := randf_range(400.0, 1800.0)
	var strike_ground := Vector3(center_pos.x + cos(ang) * dist, 0.0, center_pos.z + sin(ang) * dist)
	var cloud_origin := strike_ground + Vector3(randf_range(-100.0, 100.0), randf_range(900.0, 1300.0), randf_range(-100.0, 100.0))

	# 1. 시각적 번개 줄기 메시 빌드
	_build_lightning_mesh(cloud_origin, strike_ground)

	# 2. 하늘 섬광 트리거
	_flash_timer = 0.18

	# 3. 음속 지연 천둥 계산 (거리 d, 음속 340m/s)
	var actual_dist := center_pos.distance_to(strike_ground)
	var sound_delay := actual_dist / 340.0
	_schedule_thunder_sound(sound_delay, actual_dist)

func _build_lightning_mesh(start_pos: Vector3, end_pos: Vector3) -> void:
	var im := ImmediateMesh.new()
	var points: Array[Vector3] = [start_pos]
	var segments := 12
	var cur := start_pos

	for i in range(1, segments):
		var t := float(i) / float(segments)
		var interp := start_pos.lerp(end_pos, t)
		var jitter := Vector3(randf_range(-25.0, 25.0), randf_range(-10.0, 10.0), randf_range(-25.0, 25.0))
		points.append(interp + jitter)
	points.append(end_pos)

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(points.size() - 1):
		im.surface_add_vertex(points[i])
		im.surface_add_vertex(points[i + 1])
	im.surface_end()

	if _bolt_mesh_instance:
		_bolt_mesh_instance.mesh = im

func _schedule_thunder_sound(delay_sec: float, dist_m: float) -> void:
	# 사운드 플레이어가 구현될 때 연결 가능한 이벤트/타이머 처리
	var tree := get_tree()
	if not tree:
		return
	var t := tree.create_timer(delay_sec)
	t.timeout.connect(func():
		# 천둥 지연 도달 (디버그 로그 또는 오디오 재생)
		pass
	)

func set_lightning_enabled(enabled: bool) -> void:
	_is_active = enabled
	if not enabled:
		_flash_timer = 0.0
		if _bolt_mesh_instance:
			_bolt_mesh_instance.mesh = null
		if sun_light:
			sun_light.light_energy = _original_light_energy
