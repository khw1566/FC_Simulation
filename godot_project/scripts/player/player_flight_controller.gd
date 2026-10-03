extends CharacterBody3D
class_name PlayerFlightController

signal speed_changed(current_speed_kmh: float, gear: int, max_gear: int, accel: float, altitude_m: float, gravity_enabled: bool, mode_name: String)
signal collision_toggled(is_enabled: bool)
signal gravity_toggled(is_enabled: bool)
signal terrain_mode_toggled(is_simple: bool)
signal player_mode_changed(mode_name: String)

enum PlayerMode {
	DEBUG_FLIGHT,
	DEBUG_GROUND
}
var current_mode: PlayerMode = PlayerMode.DEBUG_FLIGHT

# 디버그-비행 기어(최고속도 단계) 설정: 총 7단계 (1단~7단)
# 1단(탐색/보행 30m/s=108km/h), 2단(순항 90m/s=324km/h), 3단(고속 240m/s=864km/h), 4단(초음속 600m/s=2,160km/h),
# 5단(마하 3 1020m/s=3,672km/h), 6단(마하 6 2040m/s=7,344km/h), 7단(마하 10 3400m/s=12,240km/h 극초음속)
const FLIGHT_GEAR_MAX_SPEEDS: Array[float] = [30.0, 90.0, 240.0, 600.0, 1020.0, 2040.0, 3400.0]
var flight_gear: int = 1

# 디버그-지상 기어 설정: 4 ~ 200 km/h 범위 5단계 (m/s 환산: km/h / 3.6)
# 1단: 4 km/h (보행), 2단: 20 km/h (조깅/자전거), 3단: 60 km/h (도심 주행), 4단: 100 km/h (고속 주행), 5단: 200 km/h (초고속 지상 점검)
const GROUND_GEAR_SPEEDS_KMH: Array[float] = [4.0, 20.0, 60.0, 100.0, 200.0]
var ground_gear: int = 1

# 가속도 5단계 비율 프리셋: 현재 기어 최고속도의 20%, 40%, 60%, 80%, 100% (1초당 도달율 비례)
const ACCEL_PERCENT_STEPS: Array[float] = [0.20, 0.40, 0.60, 0.80, 1.00]
var current_accel_step: int = 2 # 기본 3단계 (60% 수준)
var acceleration: float = 50.0

## 현재 기어 최고속도와 가속도 비율을 곱하여 실제 가속도(m/s^2)를 산출
func get_effective_acceleration() -> float:
	var max_spd: float = FLIGHT_GEAR_MAX_SPEEDS[flight_gear - 1]
	var pct: float = ACCEL_PERCENT_STEPS[current_accel_step]
	# 최소 10.0 m/s^2 보장
	return maxf(max_spd * pct, 10.0)

## 현재 가속도 비율 퍼센트 정수 반환 (20, 40, 60, 80, 100)
func get_accel_percent() -> int:
	return int(round(ACCEL_PERCENT_STEPS[current_accel_step] * 100.0))


@export var deceleration: float = 40.0   # 관성 감속도 (m/s^2)
@export var mouse_sensitivity: float = 0.003
@export var building_road_manager: Node
@export var terrain_chunk_manager: Node

# 중력 시스템 설정
var is_gravity_enabled: bool = false # 기본은 자유 비행 모드
const GRAVITY_ACCEL: float = 9.8 # 지구 중력 9.8 m/s^2
var _vertical_velocity: float = 0.0

# 컨트롤(Ctrl) 연속 클릭(더블클릭) 감지 타이머 변수
var _last_ctrl_press_time: float = -1.0
const CTRL_DOUBLE_CLICK_THRESHOLD: float = 0.35 # 0.35초 이내 연속 누름 시 더블클릭 인정

var is_collision_enabled: bool = true # 지형 충돌 켜짐/꺼짐 플래그
var _yaw: float = 0.0
var _pitch: float = 0.0
var _target_velocity: Vector3 = Vector3.ZERO
var map_navigation_active: bool = false
var _is_inside_tunnel: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var col_shape_node: CollisionShape3D = $CollisionShape3D
var distortion_rect: ColorRect = null

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_init_spawn_position()
	_load_user_settings()
	_setup_collision_shape()
	emit_speed_signal()
	collision_toggled.emit(is_collision_enabled)
	gravity_toggled.emit(is_gravity_enabled)

func _load_user_settings() -> void:
	var root = get_tree().root
	if root.has_node("UserSettingsService"):
		var settings = root.get_node("UserSettingsService")
		if settings:
			current_accel_step = clampi(settings.flight_accel_step, 0, ACCEL_PERCENT_STEPS.size() - 1)
			flight_gear = clampi(settings.flight_gear, 1, FLIGHT_GEAR_MAX_SPEEDS.size())
			mouse_sensitivity = float(settings.mouse_sensitivity)
			is_gravity_enabled = bool(settings.is_gravity_enabled)
			is_collision_enabled = bool(settings.is_collision_enabled)
	acceleration = get_effective_acceleration()
	print("[PlayerFlightController] Loaded persistent settings: Accel Step %d (%d%%), Gear %d" % [
		current_accel_step + 1, get_accel_percent(), flight_gear
	])

func _save_flight_settings() -> void:
	var root = get_tree().root
	if root.has_node("UserSettingsService"):
		var settings = root.get_node("UserSettingsService")
		if settings:
			settings.flight_accel_step = current_accel_step
			settings.flight_gear = flight_gear
			settings.mouse_sensitivity = mouse_sensitivity
			settings.is_gravity_enabled = is_gravity_enabled
			settings.is_collision_enabled = is_collision_enabled
			settings.save_settings()

func _init_spawn_position() -> void:
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			global_position = svc.selected_map.spawn_position

func _setup_collision_shape() -> void:
	if not col_shape_node:
		col_shape_node = CollisionShape3D.new()
		col_shape_node.name = "CollisionShape3D"
		add_child(col_shape_node)

	var sphere := SphereShape3D.new()
	sphere.radius = 1.8 # 플레이어 충돌 반경 1.8m
	col_shape_node.shape = sphere
	col_shape_node.disabled = !is_collision_enabled

func reset_map_travel_motion() -> void:
	velocity = Vector3.ZERO
	_target_velocity = Vector3.ZERO
	_vertical_velocity = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if map_navigation_active:
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -deg_to_rad(85), deg_to_rad(85))
		
		rotation.y = _yaw
		if camera:
			camera.rotation.x = _pitch

	if event is InputEventKey and event.pressed and not event.echo:
		# 0. G 키: 플레이어 상태 전환 (디버그-비행 <-> 디버그-지상)
		if event.keycode == KEY_G:
			toggle_player_mode()

		# 1. 최고속도 기어 전환 [Shift]
		elif event.keycode == KEY_SHIFT:
			if current_mode == PlayerMode.DEBUG_FLIGHT:
				flight_gear += 1
				if flight_gear > FLIGHT_GEAR_MAX_SPEEDS.size():
					flight_gear = 1
			else:
				ground_gear += 1
				if ground_gear > GROUND_GEAR_SPEEDS_KMH.size():
					ground_gear = 1
			_save_flight_settings()
			emit_speed_signal()

		# 2. 가속도 5단계 비율 토글 (20% ~ 100% 최고속도 비례) [Z, X]
		elif event.keycode == KEY_X:
			if current_mode == PlayerMode.DEBUG_FLIGHT:
				current_accel_step = (current_accel_step + 1) % ACCEL_PERCENT_STEPS.size()
				acceleration = get_effective_acceleration()
				_save_flight_settings()
				emit_speed_signal()
				print("[PlayerFlightController] Accel Ratio Step %d/5: %d%% (%.1f m/s²)" % [
					current_accel_step + 1, get_accel_percent(), acceleration
				])
		elif event.keycode == KEY_Z:
			if current_mode == PlayerMode.DEBUG_FLIGHT:
				current_accel_step = (current_accel_step - 1 + ACCEL_PERCENT_STEPS.size()) % ACCEL_PERCENT_STEPS.size()
				acceleration = get_effective_acceleration()
				_save_flight_settings()
				emit_speed_signal()
				print("[PlayerFlightController] Accel Ratio Step %d/5: %d%% (%.1f m/s²)" % [
					current_accel_step + 1, get_accel_percent(), acceleration
				])

		# 3. 컨트롤(Ctrl) 연속 클릭(더블클릭) 감지 -> 중력 작용 On/Off 토글
		elif event.keycode == KEY_CTRL:
			var now: float = Time.get_ticks_msec() / 1000.0
			if _last_ctrl_press_time > 0.0 and (now - _last_ctrl_press_time) <= CTRL_DOUBLE_CLICK_THRESHOLD:
				# 더블클릭 발생
				is_gravity_enabled = !is_gravity_enabled
				_vertical_velocity = 0.0
				_save_flight_settings()
				gravity_toggled.emit(is_gravity_enabled)
				emit_speed_signal()
				print("[PlayerFlightController] Gravity Toggled via Double-Ctrl: ", "ON" if is_gravity_enabled else "OFF")
				_last_ctrl_press_time = -1.0 # 리셋
			else:
				_last_ctrl_press_time = now

		# 4. C 키: 지형 충돌 On / Off 토글
		elif event.keycode == KEY_C:
			is_collision_enabled = !is_collision_enabled
			_update_active_collision()
			_save_flight_settings()
			collision_toggled.emit(is_collision_enabled)
			print("[PlayerFlightController] Terrain collision: ", "ENABLED" if is_collision_enabled else "DISABLED")

		# 5. T 키: 지형 렌더링 모드 토글 (위성 정밀 피복 텍스처 <-> 심플 등고선)
		elif event.keycode == KEY_T:
			if terrain_chunk_manager and terrain_chunk_manager.has_method("toggle_terrain_render_mode"):
				var mode: bool = terrain_chunk_manager.toggle_terrain_render_mode()
				terrain_mode_toggled.emit(mode)
				print("[PlayerFlightController] Switched Terrain Style to: ", "등고선 심플 모드" if mode else "위성 정밀 피복 모드")

		# 6. F2 키: 맵 선택 메뉴로 복귀
		elif event.keycode == KEY_F2:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().change_scene_to_file("res://scenes/ui/map_selection_menu.tscn")

func toggle_player_mode() -> void:
	if current_mode == PlayerMode.DEBUG_FLIGHT:
		current_mode = PlayerMode.DEBUG_GROUND
		is_gravity_enabled = true
	else:
		current_mode = PlayerMode.DEBUG_FLIGHT
		is_gravity_enabled = false
	_vertical_velocity = 0.0
	gravity_toggled.emit(is_gravity_enabled)
	player_mode_changed.emit(get_mode_name())
	emit_speed_signal()
	print("[PlayerFlightController] Switched Player Mode to: %s" % get_mode_name())

func get_mode_name() -> String:
	return "디버그-지상" if current_mode == PlayerMode.DEBUG_GROUND else "디버그-비행"

func _physics_process(delta: float) -> void:
	if map_navigation_active:
		reset_map_travel_motion()
		return
	# 터널 통과 영역 실시간 판정
	_check_tunnel_exception()

	var forward := -transform.basis.z
	var right := transform.basis.x
	var up := Vector3.UP

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir += forward
	if Input.is_key_pressed(KEY_S):
		input_dir -= forward
	if Input.is_key_pressed(KEY_D):
		input_dir += right
	if Input.is_key_pressed(KEY_A):
		input_dir -= right

	if current_mode == PlayerMode.DEBUG_GROUND:
		# 지상 모드: 수평 방향으로만 이동 벡터 한정 (카메라 피치 기울임에 따른 하늘/땅 방향 쏠림 방지)
		input_dir.y = 0.0
		if input_dir.length_squared() > 0.001:
			input_dir = input_dir.normalized()

		# 점프 기능 (Space)
		if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
			_vertical_velocity = 7.5

		# 4 ~ 200 km/h 5단계 즉각 속도 제어 (가속도 미적용: 0ms 즉발 반응)
		var target_speed_ms: float = (GROUND_GEAR_SPEEDS_KMH[ground_gear - 1]) / 3.6
		if input_dir.length_squared() > 0.001:
			velocity.x = input_dir.x * target_speed_ms
			velocity.z = input_dir.z * target_speed_ms
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		# 비행 모드: 3D 자유 비행
		if not is_gravity_enabled:
			if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
				input_dir += up
			if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
				input_dir -= up
		else:
			if Input.is_key_pressed(KEY_SPACE):
				input_dir += up * 1.5

		var max_speed: float = FLIGHT_GEAR_MAX_SPEEDS[flight_gear - 1]
		var eff_accel: float = get_effective_acceleration()
		acceleration = eff_accel

		# 수평 및 제어 가속도 (현재 기어 최고속도에 비례한 가속도 적용)
		if input_dir.length_squared() > 0.01:
			_target_velocity = input_dir.normalized() * max_speed
			velocity = velocity.move_toward(_target_velocity, eff_accel * delta)
		else:
			_target_velocity = Vector3.ZERO
			# 관성 감속도 역시 최고속도에 비례하여 자연스러운 제동 (최고속도의 50% 수준)
			var eff_decel: float = maxf(max_speed * 0.5, deceleration)
			velocity = velocity.move_toward(Vector3.ZERO, eff_decel * delta)

	# 중력 작용 처리
	if is_gravity_enabled:
		if not is_on_floor():
			_vertical_velocity -= GRAVITY_ACCEL * delta * 2.5 # 체감도 높은 낙하 가속
		else:
			if _vertical_velocity < 0.0:
				_vertical_velocity = 0.0
		velocity.y = _vertical_velocity
	else:
		_vertical_velocity = 0.0

	# 초고속 비행 시 지형 뚫림(Tunneling) 방지를 위한 터널 예외 처리
	_check_tunnel_exception()

	# 현재 좌표의 실제 지형 고도(Ground Elevation) 측정
	var terrain_mgr = terrain_chunk_manager
	if not terrain_mgr:
		terrain_mgr = get_parent().get_node_or_null("TerrainManager")

	var ground_y := -999.0
	if terrain_mgr and terrain_mgr.has_method("get_terrain_elevation"):
		ground_y = float(terrain_mgr.call("get_terrain_elevation", global_position.x, global_position.z))

	# [일방통행 상향 통과 (One-Way Upward Pass)]:
	# 플레이어가 지형 표면보다 아래(global_position.y < ground_y)로 뚫고 들어갔을 때,
	# 지형 아래에서 위로 올라오는 상승 움직임이 지형 메쉬 충돌체에 가로막히지 않도록 일시적으로 충돌체를 바이패스하고
	# 상향 탈출 속도를 보장하여 지상 위로 즉시 복귀시킴
	var is_underground := (ground_y > -900.0 and global_position.y < (ground_y - 0.5))

	if is_underground:
		# 지형 밑에 갇힌 상태: 충돌을 일시 해제하여 자유롭게 위로 뚫고 올라올 수 있게 허용
		if col_shape_node and not col_shape_node.disabled:
			col_shape_node.disabled = true

		# 만약 하강 중이거나 정지해 있다면 즉시 지표면 위로 완만하게 밀어 올림
		if velocity.y <= 0.0 and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_Q):
			global_position.y = lerpf(global_position.y, ground_y + 3.0, 10.0 * delta)
			velocity.y = maxf(velocity.y, 15.0)
		elif velocity.y > 0.0:
			# 플레이어가 위로 상승 조작(E 또는 Space) 중이면 지형을 뚫고 통과하여 올라오도록 가속
			velocity.y = maxf(velocity.y, 25.0)
	else:
		# 지상 위로 정상 복귀 시 충돌 상태 원상 복구
		_update_active_collision()

	move_and_slide()

	# 맵 하부 일정 깊이 이하 무한 추락 방지 안전 리미터
	var min_safe_y: float = (ground_y - 20.0) if ground_y > -900.0 else -68.0
	if global_position.y < min_safe_y:
		global_position.y = min_safe_y + 1.0
	var cur_speed_ms := velocity.length()
	var max_ref_speed := FLIGHT_GEAR_MAX_SPEEDS[-1] if current_mode == PlayerMode.DEBUG_FLIGHT else (GROUND_GEAR_SPEEDS_KMH[-1] / 3.6)
	var speed_ratio := clampf(cur_speed_ms / max_ref_speed, 0.0, 1.0)
	
	_update_visual_distortion(speed_ratio, delta)
	emit_speed_signal()

func _check_tunnel_exception() -> void:
	if not building_road_manager:
		building_road_manager = get_parent().get_node_or_null("BuildingRoadManager")

	if building_road_manager and building_road_manager.has_method("is_position_inside_tunnel"):
		var in_tunnel: bool = bool(building_road_manager.call("is_position_inside_tunnel", global_position))
		if in_tunnel != _is_inside_tunnel:
			_is_inside_tunnel = in_tunnel
			_update_active_collision()
			if _is_inside_tunnel:
				print("[PlayerFlightController] Entered Tunnel Zone -> Collision bypassed.")
			else:
				print("[PlayerFlightController] Exited Tunnel Zone -> Collision restored.")

func _update_active_collision() -> void:
	if col_shape_node:
		var should_disable: bool = (!is_collision_enabled) or _is_inside_tunnel
		col_shape_node.disabled = should_disable

func _update_visual_distortion(speed_ratio: float, delta: float) -> void:
	if camera:
		var target_fov: float = 70.0 + pow(speed_ratio, 0.85) * 45.0
		camera.fov = lerpf(camera.fov, target_fov, 5.0 * delta)

func emit_speed_signal() -> void:
	var speed_kmh := velocity.length() * 3.6
	var alt_m := global_position.y
	var gear := flight_gear if current_mode == PlayerMode.DEBUG_FLIGHT else ground_gear
	var max_gear := FLIGHT_GEAR_MAX_SPEEDS.size() if current_mode == PlayerMode.DEBUG_FLIGHT else GROUND_GEAR_SPEEDS_KMH.size()
	var accel_val := get_effective_acceleration() if current_mode == PlayerMode.DEBUG_FLIGHT else 0.0
	speed_changed.emit(speed_kmh, gear, max_gear, accel_val, alt_m, is_gravity_enabled, get_mode_name())
