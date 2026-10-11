extends Control
class_name MapFovDrawer

# 플레이어의 시야각(FOV) 콘(Cone)을 반투명하게 렌더링하는 전용 CanvasItem 드로어
var cone_radius: float = 40.0
var cone_angle_deg: float = 70.0
var cone_direction: float = 0.0 # 라디안

# 흑백 모노크롬 규격의 반투명 원추형 필
const CONE_FILL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.15)
const CONE_EDGE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)

func update_fov(radius: float, fov_deg: float, angle_rad: float) -> void:
	cone_radius = radius
	cone_angle_deg = fov_deg
	cone_direction = angle_rad
	queue_redraw()

func _draw() -> void:
	var half_fov := deg_to_rad(cone_angle_deg * 0.5)
	var start_angle := cone_direction - half_fov - PI * 0.5
	var end_angle := cone_direction + half_fov - PI * 0.5
	
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	
	points.append(Vector2.ZERO)
	colors.append(CONE_FILL_COLOR)
	
	var segments := 16
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var cur_a := lerpf(start_angle, end_angle, t)
		var p := Vector2(cos(cur_a), sin(cur_a)) * cone_radius
		points.append(p)
		colors.append(CONE_FILL_COLOR)
	
	if points.size() >= 3:
		draw_polygon(points, colors)
		# 외곽 경계선 렌더링
		draw_line(Vector2.ZERO, points[1], CONE_EDGE_COLOR, 1.5, true)
		draw_line(Vector2.ZERO, points[-1], CONE_EDGE_COLOR, 1.5, true)
		for i in range(1, points.size() - 1):
			draw_line(points[i], points[i + 1], CONE_EDGE_COLOR, 1.2, true)
