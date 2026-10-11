extends Control
class_name FlightVectorHUDView

## 비행 시뮬레이션 디버깅용 3D 벡터 HUD
## 화면 중앙에서 기체의 실제 이동 속도 벡터 및 가속/진행 방향을 선명한 녹색(#00ff66) 화살표 및 벡터 제원으로 시각화

@export var player_node: CharacterBody3D
@export var camera_node: Camera3D

var is_vector_hud_visible: bool = true

# 화살표 스타일 파라미터 (녹색 테마)
const VECTOR_COLOR := Color(0.0, 1.0, 0.45, 0.95)
const VECTOR_SHADOW_COLOR := Color(0.0, 0.2, 0.08, 0.5)
const CENTER_RETICLE_COLOR := Color(0.0, 1.0, 0.45, 0.55)
const HORIZON_COLOR := Color(0.0, 1.0, 0.45, 0.40)
const PITCH_LADDER_COLOR := Color(0.0, 1.0, 0.45, 0.60)

# 평활화(Smoothing) 변수
var _smoothed_screen_vec: Vector2 = Vector2.ZERO
var _current_roll: float = 0.0
var _current_pitch: float = 0.0
var _font: Font = null

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	if not is_vector_hud_visible:
		queue_redraw()
		return

	if not player_node or not camera_node:
		var root = get_tree().root
		if not player_node:
			player_node = root.find_child("Player", true, false) as CharacterBody3D
		if player_node and not camera_node:
			camera_node = player_node.find_child("Camera3D", true, false) as Camera3D

	if player_node and camera_node:
		var cam_basis: Basis = camera_node.global_transform.basis
		var vel: Vector3 = player_node.velocity

		# 1. 속도 벡터 방향 분해 (카메라 기준: x=우, y=상, -z=전)
		var local_x: float = cam_basis.x.dot(vel)
		var local_y: float = cam_basis.y.dot(vel)

		var cur_speed_kmh: float = vel.length() * 3.6

		# 2. 벡터 크기 스케일링 규칙 (0~200 km/h 구간만 비례 증가, 그 이상은 70px 고정)
		# 0km/h -> 0px, 200km/h -> 70px, 200km/h 초과 -> 70px 유지
		var speed_factor: float = clampf(cur_speed_kmh / 200.0, 0.0, 1.0)
		var max_arrow_length: float = 70.0
		var arrow_len: float = speed_factor * max_arrow_length

		var dir_2d := Vector2(local_x, -local_y)
		var target_vec := Vector2.ZERO
		if dir_2d.length_squared() > 0.001 and cur_speed_kmh > 0.5:
			target_vec = dir_2d.normalized() * arrow_len

		_smoothed_screen_vec = _smoothed_screen_vec.lerp(target_vec, 14.0 * delta)

		# 3. 플레이어 롤(Roll) 및 피치(Pitch) 계산
		# 현재 기체/카메라 회전 쿼리
		var target_roll: float = camera_node.global_rotation.z
		var target_pitch: float = camera_node.global_rotation.x
		_current_roll = lerp_angle(_current_roll, target_roll, 10.0 * delta)
		_current_pitch = lerpf(_current_pitch, target_pitch, 10.0 * delta)

	queue_redraw()

func _draw() -> void:
	if not is_vector_hud_visible:
		return

	var center := size * 0.5

	# 1. 비행 계기 롤(Roll) 인공 수평선 (화면 중앙 기준 얇은 점선/라인)
	_draw_roll_horizon(center, _current_roll)

	# 2. 플레이어 피치선 (Pitch Ladder: -20° ~ +20° 얇은 수평 눈금바)
	_draw_pitch_ladder(center, _current_pitch, _current_roll)

	# 3. 화면 중앙 조준 레티클 (얇은 1px 십자선 및 정밀 조준원)
	draw_arc(center, 8.0, 0.0, TAU, 24, CENTER_RETICLE_COLOR, 1.0)
	draw_circle(center, 1.5, VECTOR_COLOR)
	draw_line(center + Vector2(-16, 0), center + Vector2(-10, 0), CENTER_RETICLE_COLOR, 1.0)
	draw_line(center + Vector2(10, 0), center + Vector2(16, 0), CENTER_RETICLE_COLOR, 1.0)
	draw_line(center + Vector2(0, -16), center + Vector2(0, -10), CENTER_RETICLE_COLOR, 1.0)
	draw_line(center + Vector2(0, 10), center + Vector2(0, 16), CENTER_RETICLE_COLOR, 1.0)

	var vec_len := _smoothed_screen_vec.length()
	if vec_len < 2.5:
		return

	var end_pt := center + _smoothed_screen_vec
	var dir := _smoothed_screen_vec.normalized()
	var normal := Vector2(-dir.y, dir.x)

	# 4. 순수 얇은 선(Thin Line) 화살표 샤프트 (굵기 1.5px)
	draw_line(center + dir * 9.0, end_pt, VECTOR_COLOR, 1.5)

	# 5. 순수 얇은 선(Thin Line) 화살표 촉 (V자형 2개의 얇은 선, 면 채움 배제)
	var head_len: float = clampf(vec_len * 0.3, 7.0, 12.0)
	var head_w: float = head_len * 0.55
	var h_left := end_pt - dir * head_len + normal * head_w
	var h_right := end_pt - dir * head_len - normal * head_w

	draw_line(end_pt, h_left, VECTOR_COLOR, 1.5)
	draw_line(end_pt, h_right, VECTOR_COLOR, 1.5)

	# 6. 미니멀 디지털 벡터 정보 (10px 컴팩트 텍스트)
	if player_node and _font:
		var cur_speed_kmh: float = player_node.velocity.length() * 3.6
		var pitch_deg: float = rad_to_deg(_current_pitch)
		var text_str := "%.0f km/h" % cur_speed_kmh
		var text_pos := end_pt + dir * 10.0 + Vector2(-18, 4)
		draw_string(_font, text_pos + Vector2(1, 1), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, VECTOR_SHADOW_COLOR)
		draw_string(_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, VECTOR_COLOR)

## 롤(Roll) 기준선 그리기: 화면 중앙을 가로지르는 비행 기준 지평선
func _draw_roll_horizon(center: Vector2, roll_rad: float) -> void:
	var roll_dir := Vector2(cos(roll_rad), sin(roll_rad))
	var p_left := center - roll_dir * 110.0
	var p_left_inner := center - roll_dir * 30.0
	var p_right_inner := center + roll_dir * 30.0
	var p_right := center + roll_dir * 110.0

	# 중앙을 비워둔 좌우 얇은 기준선 (선폭 1.0px)
	draw_line(p_left, p_left_inner, HORIZON_COLOR, 1.0)
	draw_line(p_right_inner, p_right, HORIZON_COLOR, 1.0)

	# 롤 기준 각도 표시 틱(Tick)
	var roll_norm := Vector2(-roll_dir.y, roll_dir.x)
	draw_line(p_left, p_left + roll_norm * 5.0, HORIZON_COLOR, 1.0)
	draw_line(p_right, p_right + roll_norm * 5.0, HORIZON_COLOR, 1.0)

## 피치선 (Pitch Ladder) 그리기: 상하 ±10°, ±20° 얇은 계단형 수평선
func _draw_pitch_ladder(center: Vector2, pitch_rad: float, roll_rad: float) -> void:
	var pitch_deg: float = rad_to_deg(pitch_rad)
	var px_per_deg: float = 3.2 # 1도당 3.2px 변위

	var roll_dir := Vector2(cos(roll_rad), sin(roll_rad))
	var pitch_up := Vector2(-roll_dir.y, roll_dir.x)

	var pitch_steps: Array[float] = [-20.0, -10.0, 10.0, 20.0]
	for step_deg in pitch_steps:
		# 현재 피치 대비 상대 위치
		var delta_deg := step_deg - (-pitch_deg)
		if abs(delta_deg) > 28.0:
			continue

		var y_offset := delta_deg * px_per_deg
		var rung_center := center - pitch_up * y_offset

		var half_w: float = 24.0 if abs(step_deg) == 10.0 else 32.0
		var r_left := rung_center - roll_dir * half_w
		var r_right := rung_center + roll_dir * half_w

		# 피치 바 얇은 선 그리기 (상승은 꺾쇠 상향, 하강은 점선 스타일 꺾쇠)
		draw_line(r_left, r_right, PITCH_LADDER_COLOR, 1.0)
		var tick_dir := pitch_up if step_deg > 0.0 else -pitch_up
		draw_line(r_left, r_left + tick_dir * 4.0, PITCH_LADDER_COLOR, 1.0)
		draw_line(r_right, r_right + tick_dir * 4.0, PITCH_LADDER_COLOR, 1.0)

		# 각도 숫자 표기
		if _font:
			var sign_str := "%+d°" % int(step_deg)
			var font_pos := r_right + Vector2(4, 3)
			draw_string(_font, font_pos, sign_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PITCH_LADDER_COLOR)

func set_hud_visible(val: bool) -> void:
	is_vector_hud_visible = val
	visible = val
	queue_redraw()
