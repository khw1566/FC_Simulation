extends Camera3D
## 선박 프리뷰의 회전, 확대 및 시점 초기화만 담당한다.

var yaw := 0.65
var pitch := 0.40
var distance := 36.0
var dragging := false
var target := Vector3(0, 3, 0)


func _ready() -> void:
	_update_view()


func reset_view() -> void:
	yaw = 0.65
	pitch = 0.40
	distance = 36.0
	_update_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(16.0, distance - 2.0)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(70.0, distance + 2.0)
		_update_view()
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.008, -0.15, 1.3)
		_update_view()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			reset_view()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _update_view() -> void:
	position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at(target, Vector3.UP)
