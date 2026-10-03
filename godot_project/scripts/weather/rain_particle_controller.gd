extends Node3D
class_name RainParticleController

## 플레이어 동기화 3D 강우 파티클 제어기

@export var player_node: CharacterBody3D
@export var rain_intensity: float = 0.0 # 0.0 ~ 1.0
@export var rain_color: Color = Color(0.75, 0.85, 0.95, 0.55)

var _particles: GPUParticles3D
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
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mesh.material = mat

	_particles.draw_pass_1 = quad_mesh

	# 프로세스 머티리얼 (GPU 파티클 낙하 및 분산)
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = Vector3(45.0, 12.0, 45.0)
	proc_mat.direction = Vector3(0.0, -1.0, 0.0)
	proc_mat.spread = 4.0
	proc_mat.initial_velocity_min = 40.0
	proc_mat.initial_velocity_max = 60.0
	proc_mat.gravity = Vector3(0.0, -9.8, 0.0)
	
	_particles.process_material = proc_mat
	add_child(_particles)
	_update_visibility()
	print("[RainParticleController] Initialized Rain Particle System (local_coords=false).")

func _process(_delta: float) -> void:
	if not _is_active or not _particles or rain_intensity <= 0.01:
		return

	if player_node:
		# 플레이어 머리 위 15m 지점에 파티클 박스 유지
		global_position = player_node.global_position + Vector3(0.0, 15.0, 0.0)

		# 플레이어 이동 속도에 따라 빗줄기 낙하 각도 및 속도 조정
		var vel := player_node.velocity
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
	var should_emit: bool = _is_active and (rain_intensity > 0.01)
	_particles.emitting = should_emit
	_particles.visible = should_emit
	if should_emit:
		_particles.amount = maxi(100, int(3000 * rain_intensity))

