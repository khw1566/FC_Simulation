extends Control
## 선택된 행정구역을 지도 좌표에 맞춰 표시한다.
var polygon := PackedVector2Array()
var world_size: float = 80000.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if polygon.size() < 3:
		return
	var points := PackedVector2Array()
	for p in polygon:
		points.append((p / world_size + Vector2(0.5, 0.5)) * size)
	points.append(points[0])
	draw_polyline(points, Color.BLACK, 4.0, true)
	draw_polyline(points, Color.WHITE, 1.5, true)
