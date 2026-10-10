extends Node3D
class_name RainParticleController

## 플레이어 동기화 3D 강우 파티클 제어기

@export var player_node: CharacterBody3D
@export var rain_intensity: float = 0.0 # 0.0 ~ 1.0
@export var rain_color: Color = Color(0.75, 0.85, 0.95, 0.55)

const RAIN_HALF_EXTENT := 60.0
const RAIN_CLOUD_BASE := 1200.0 # 이 고도 위로는 빗줄기를 줄이고 구름 위에서는 끈다
const RAIN_CLOUD_TOP := 2600.0

var _particles: GPUParticles3D
var _altitude_scale := 1.0
var _is_active: bool = true

func _ready() -> void:
	_create_rain_particle_system()

func _create_rain_particle_system() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainGPUParticles"
	_particles.amount = 3000
	_particles.lifetime = 1.0
	_particles.preprocess = 0.5
	_particles.speed_scale = 1.2
	_particles.explosiveness = 0.0
	_particles.randomness = 0.2
	_particles.fixed_fps = 60
	_particles.local_coords = false

	# 파티클 드로우 패스: 세로로 긴 라인/리본 쿼드 (가시성 확보를 위해 폭 0.08m, 길이 2.5m)
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.08, 2.5)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.92, 1.0, 0.75)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 세로축만 카메라를 향해 빗줄기가 항상 연직으로 보이게 한다.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	quad_mesh.material = mat

	_particles.draw_pass_1 = quad_mesh

	# 프로세스 머티리얼 (GPU 파티클 낙하 및 분산)
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(RAIN_HALF_EXTENT, 12.0, RAIN_HALF_EXTENT)
	proc_mat.direction = Vector3(0.0, -1.0, 0.0)
	proc_mat.spread = 4.0
	proc_mat.initial_velocity_min = 40.0
	proc_mat.initial_velocity_max = 60.0
	proc_mat.gravity = Vector3(0.0, -9.8, 0.0)
	
	_particles.process_material = proc_mat
	# 기본 가시 AABB(8m 상자)가 화면 밖으로 나가면 파티클 전체가 컬링되어
	# 특정 각도·시점에서만 비가 보였다. 방출 상자와 낙하 거리를 모두 덮도록 넓힌다.
	_particles.visibility_aabb = AABB(Vector3(-RAIN_HALF_EXTENT - 20.0, -90.0, -RAIN_HALF_EXTENT - 20.0), Vector3(2.0 * RAIN_HALF_EXTENT + 40.0, 120.0, 2.0 * RAIN_HALF_EXTENT + 40.0))
	add_child(_particles)
	_update_visibility()
	print("[RainParticleController] Initialized Rain Particle System (local_coords=false).")

func _process(_delta: float) -> void:
	if not _is_active or not _particles or rain_intensity <= 0.01 or not player_node:
		return

	if player_node:
		# 빠르게 비행해도 방출 상자가 뒤처지지 않도록 진행 방향 앞쪽에 둔다.
		var vel := player_node.velocity
		global_position = player_node.global_position + Vector3(0.0, 15.0, 0.0) + vel * 0.6
		# 구름층 위에서는 비가 보이지 않는다.
		var alt_scale := 1.0 - smoothstep(RAIN_CLOUD_BASE, RAIN_CLOUD_TOP, player_node.global_position.y)
		if absf(alt_scale - _altitude_scale) > 0.05 or (alt_scale <= 0.0) != (_altitude_scale <= 0.0):
			_altitude_scale = alt_scale
			_update_visibility()

		# 플레이어 이동 속도에 따라 빗줄기 낙하 각도 및 속도 조정
		if _particles.process_material is ParticleProcessMaterial:
			var pmat := _particles.process_material as ParticleProcessMaterial
			var fall_dir := Vector3(-vel.x * 0.02, -45.0, -vel.z * 0.02).normalized()
			pmat.direction = fall_dir

func set_rain_intensity(val: float) -> void:
	rain_intensity = clampf(val, 0.0, 1.0)
	_update_visibility()
	print("[RainParticleController] Set rain intensity: %.2f (emitting=%s, visible=%s)" % [rain_intensity, _particles.emitting if _particles else false, _particles.visible if _particles else false])

func set_rain_enabled(enabled: bool) -> void:
	_is_active = enabled
	_update_visibility()

func _update_visibility() -> void:
	if not _particles:
		return
	var effective := rain_intensity * _altitude_scale
	var should_emit: bool = _is_active and (effective > 0.01)
	_particles.emitting = should_emit
	_particles.visible = should_emit
	if should_emit:
		_particles.amount = maxi(100, int(4000 * effective))

