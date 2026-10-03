extends Node3D
class_name CloudClusterManager

## 고도별 다층 구름 생성 및 절차적 합성 관리자
## 저고도/중고도/고고도별 구름 종류(적운, 층적운, 권운, 적란운)를 사전 생성하고
## 기상 상태 및 그래픽 품질 프리셋(노트북 경량화 포함)에 따라 동적으로 제어
## 플레이어 비행체 관통 시 실시간 후류 터널(Wake Cavity) 상호작용 전달

@export var player_node: Node3D
@export var day_night_service: Node
@export var spawn_radius: float = 4500.0
@export var wind_velocity: Vector3 = Vector3(8.0, 0.0, 4.0)

# 구름 셰이더 리소스
var _cloud_shader: Shader = null
var _is_active: bool = true

# 품질 레벨 (0: Ultra, 1: High, 2: Medium, 3: Laptop/Low, 4: Off)
var _current_quality: int = 1

# 사전 생성된 고도별 구름 볼륨 풀
var _cumulus_nodes: Array[MeshInstance3D] = []
var _stratocumulus_nodes: Array[MeshInstance3D] = []
var _cirrus_nodes: Array[MeshInstance3D] = []
var _cumulonimbus_nodes: Array[MeshInstance3D] = []

# 비행체 상호작용 추적 변수
var _prev_player_pos: Vector3 = Vector3.ZERO
var _current_wake_strength: float = 0.0

func _ready() -> void:
	if not day_night_service:
		day_night_service = get_node_or_null("../DayNightCycleService")
	_load_shader()
	_generate_all_cloud_presets()

func _load_shader() -> void:
	var shader_path := "res://shaders/volumetric_cloud.gdshader"
	var res = load(shader_path)
	if res is Shader:
		_cloud_shader = res
	else:
		push_warning("[CloudClusterManager] Failed to load shader: " + shader_path)

func _generate_all_cloud_presets() -> void:
	if not _cloud_shader:
		push_warning("[CloudClusterManager] Aborted generating clouds: shader is null.")
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# 1. 저고도 적운(Cumulus) 뭉게구름: 600m ~ 1,100m, Worley 구면 뭉게구름
	_cumulus_nodes = _spawn_cloud_group(
		6, 0, Vector3(950.0, 450.0, 950.0), 600.0, 1100.0,
		7.5, 0.55, 1.2, 0.5, "Cumulus", rng
	)

	# 2. 중고도 층적운(Stratocumulus) 물결 덮개구름: 1,200m ~ 2,000m, 넓고 평평함
	_stratocumulus_nodes = _spawn_cloud_group(
		4, 1, Vector3(2200.0, 320.0, 2200.0), 1200.0, 2000.0,
		5.0, 0.65, 0.6, 0.4, "Stratocumulus", rng
	)

	# 3. 고고도 권운(Cirrus) 새털구름: 2,800m ~ 4,500m, 얇고 빠른 제트기류 결
	_cirrus_nodes = _spawn_cloud_group(
		4, 2, Vector3(2800.0, 180.0, 2800.0), 2800.0, 4500.0,
		3.5, 0.40, 0.3, 1.2, "Cirrus", rng
	)

	# 4. 수직 거대 적란운(Cumulonimbus) 뇌우 모루구름: 1,200m ~ 3,500m
	_cumulonimbus_nodes = _spawn_cloud_group(
		2, 3, Vector3(2800.0, 2900.0, 2800.0), 1200.0, 1800.0,
		14.0, 0.75, 1.6, 0.8, "Cumulonimbus", rng
	)

	print("[CloudClusterManager] Generated all presets: Cumulus(%d), Strato(%d), Cirrus(%d), CB(%d)" % [
		_cumulus_nodes.size(), _stratocumulus_nodes.size(), _cirrus_nodes.size(), _cumulonimbus_nodes.size()
	])

func _spawn_cloud_group(
	count: int, type_id: int, base_box_size: Vector3,
	min_alt: float, max_alt: float, density: float,
	coverage: float, puff: float, curl: float,
	group_name: String, rng: RandomNumberGenerator
) -> Array[MeshInstance3D]:
	var group: Array[MeshInstance3D] = []

	var center_pos := Vector3.ZERO
	if player_node:
		center_pos = player_node.global_position

	for i in range(count):
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d" % [group_name, i]

		var var_w := rng.randf_range(0.85, 1.3) * base_box_size.x
		var var_h := rng.randf_range(0.85, 1.25) * base_box_size.y
		var var_d := rng.randf_range(0.85, 1.3) * base_box_size.z

		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mi.mesh = box
		mi.scale = Vector3(var_w, var_h, var_d)

		var mat := ShaderMaterial.new()
		mat.shader = _cloud_shader
		mat.set_shader_parameter("quality_mode", _current_quality)
		mat.set_shader_parameter("cloud_type", type_id)
		mat.set_shader_parameter("cloud_density", density * rng.randf_range(0.85, 1.15))
		mat.set_shader_parameter("coverage", coverage * rng.randf_range(0.9, 1.1))
		mat.set_shader_parameter("puffiness", puff)
		mat.set_shader_parameter("curl_factor", curl)
		mat.set_shader_parameter("march_steps", 16)
		mat.set_shader_parameter("light_steps", 2)
		mat.set_shader_parameter("cloud_top_color", Color(0.96, 0.97, 1.0, 1.0))
		mat.set_shader_parameter("cloud_bottom_color", Color(0.60, 0.65, 0.76, 1.0))
		mat.set_shader_parameter("cloud_shadow_color", Color(0.24, 0.27, 0.36, 1.0))
		mat.set_shader_parameter("sun_direction", Vector3(0.35, -0.75, 0.25))
		mat.set_shader_parameter("time_speed", 0.025)

		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(400.0, spawn_radius)
		var px := center_pos.x + cos(ang) * dist
		var pz := center_pos.z + sin(ang) * dist
		var py := rng.randf_range(min_alt, max_alt)

		mi.position = Vector3(px, py, pz)
		mi.rotation.y = rng.randf_range(0.0, TAU)

		add_child(mi)
		group.append(mi)

	return group

func _process(delta: float) -> void:
	if not _is_active or not visible or _current_quality == 4:
		return

	var center_pos := Vector3.ZERO
	var p_pos := Vector3.ZERO
	var p_vel := Vector3.ZERO
	if player_node:
		center_pos = player_node.global_position
		p_pos = player_node.global_position
		p_vel = (p_pos - _prev_player_pos) / maxf(delta, 0.001)
		_prev_player_pos = p_pos

	var speed := p_vel.length()
	# 시뮬레이션 고속 비행 시 상호작용 후류 강도 계산
	if speed > 20.0:
		_current_wake_strength = move_toward(_current_wake_strength, clampf(speed / 150.0, 0.4, 1.0), delta * 2.0)
	else:
		_current_wake_strength = move_toward(_current_wake_strength, 0.0, delta * 0.4)

	for child in get_children():
		var mi := child as MeshInstance3D
		if mi == null or not mi.visible:
			continue

		# 바람에 의한 이동
		mi.position += wind_velocity * delta

		var diff_x: float = mi.position.x - center_pos.x
		var diff_z: float = mi.position.z - center_pos.z
		var dist_sq: float = diff_x * diff_x + diff_z * diff_z

		# 반경 이탈 시 재배치
		if dist_sq > (spawn_radius * 1.35) * (spawn_radius * 1.35):
			var forward_dir := wind_velocity.normalized()
			mi.position.x = center_pos.x - forward_dir.x * spawn_radius * 0.95 + randf_range(-600.0, 600.0)
			mi.position.z = center_pos.z - forward_dir.z * spawn_radius * 0.95 + randf_range(-600.0, 600.0)

		# 플레이어 근접 구름의 경우 비행체 통과 후류 터널 연산 전달 (품질 0~2에서만 연산)
		if _current_quality <= 2 and _current_wake_strength > 0.05 and mi.material_override is ShaderMaterial:
			var to_box := p_pos - mi.position
			var half_size := mi.scale * 0.55
			if absf(to_box.x) < half_size.x and absf(to_box.y) < half_size.y and absf(to_box.z) < half_size.z:
				# 기체가 해당 구름 박스 내부에 진입함 -> 오브젝트 로컬 좌표계로 변환
				var inv_t := mi.global_transform.affine_inverse()
				var local_p := inv_t * p_pos
				var local_v := inv_t.basis * p_vel
				var mat := mi.material_override as ShaderMaterial
				mat.set_shader_parameter("player_pos_obj", local_p)
				mat.set_shader_parameter("player_vel_obj", local_v.normalized())
				mat.set_shader_parameter("player_wake_radius", 0.16) # 구름 로컬 기준 반경
				mat.set_shader_parameter("player_wake_strength", _current_wake_strength)

## 그래픽 품질 설정 반영 (0: Ultra, 1: High, 2: Medium, 3: Laptop/Low, 4: Off)
func set_cloud_quality(quality_level: int) -> void:
	_current_quality = quality_level
	print("[CloudClusterManager] set_cloud_quality: %d" % quality_level)

	if quality_level >= 4:
		set_clouds_enabled(false)
		return
	else:
		set_clouds_enabled(true)

	# 셰이더 및 인스턴스에 품질 파라미터 적용
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi and mi.material_override is ShaderMaterial:
			var mat := mi.material_override as ShaderMaterial
			mat.set_shader_parameter("quality_mode", quality_level)

## 날씨 상태별 고도 구름 합성 제어기
func configure_composition(
	cumulus_ratio: float,
	strato_ratio: float,
	cirrus_ratio: float,
	cb_ratio: float,
	cloud_top_col: Color,
	cloud_bot_col: Color,
	shadow_col: Color
) -> void:
	# 노트북 모드일 경우 가시 구름 개수를 절반으로 자동 절감하여 성능 확보
	var density_mult: float = 0.55 if _current_quality == 3 else 1.0

	_apply_group_state(_cumulus_nodes, cumulus_ratio * density_mult, cloud_top_col, cloud_bot_col, shadow_col)
	_apply_group_state(_stratocumulus_nodes, strato_ratio * density_mult, cloud_top_col, cloud_bot_col, shadow_col)
	_apply_group_state(_cirrus_nodes, cirrus_ratio * density_mult, cloud_top_col, cloud_bot_col, shadow_col)
	_apply_group_state(_cumulonimbus_nodes, cb_ratio * density_mult, cloud_top_col, cloud_bot_col, shadow_col)

func _apply_group_state(
	group: Array[MeshInstance3D], ratio: float,
	top_c: Color, bot_c: Color, sh_c: Color
) -> void:
	var night_weight := _get_night_weight()
	var active_count: int = int(round(group.size() * ratio))
	for i in range(group.size()):
		var mi := group[i]
		var is_on := (i < active_count) and (ratio > 0.01) and (_current_quality < 4)
		mi.visible = is_on
		if is_on and mi.material_override is ShaderMaterial:
			var mat := mi.material_override as ShaderMaterial
			mat.set_shader_parameter("quality_mode", _current_quality)
			mat.set_shader_parameter("cloud_top_color", top_c)
			mat.set_shader_parameter("cloud_bottom_color", bot_c)
			mat.set_shader_parameter("cloud_shadow_color", sh_c)
			mat.set_shader_parameter("night_weight", night_weight)
			mat.set_shader_parameter("moonlight_scale", lerpf(1.0, 0.42, night_weight))
			mat.set_shader_parameter("cloud_top_color", top_c.lerp(Color(0.25, 0.30, 0.42), night_weight))
			mat.set_shader_parameter("cloud_bottom_color", bot_c.lerp(Color(0.075, 0.095, 0.15), night_weight))
			mat.set_shader_parameter("cloud_shadow_color", sh_c.lerp(Color(0.018, 0.025, 0.045), night_weight))
	for mi in group:
		if mi.material_override is ShaderMaterial:
			var inactive_mat := mi.material_override as ShaderMaterial
			inactive_mat.set_shader_parameter("night_weight", night_weight)
			inactive_mat.set_shader_parameter("moonlight_scale", lerpf(1.0, 0.42, night_weight))

func _get_night_weight() -> float:
	if not day_night_service or not ("current_time_hours" in day_night_service):
		return 0.0
	var hours := float(day_night_service.current_time_hours)
	var daylight := smoothstep(5.2, 7.8, hours) * (1.0 - smoothstep(17.0, 19.4, hours))
	return 1.0 - daylight

func set_clouds_enabled(enabled: bool) -> void:
	_is_active = enabled
	visible = enabled
	set_process(enabled)
