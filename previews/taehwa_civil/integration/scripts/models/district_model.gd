extends RefCounted
class_name DistrictModel

var id: String = ""
var name_ko: String = ""
var name_en: String = ""
var prefecture: String = ""
var city: String = ""
var admin_name: String = ""
var admin_level: int = -1
var admin_hierarchy: Array = []
var landmarks: Array = []
var polygon_points: PackedVector2Array = PackedVector2Array()
var bounds: Rect2 = Rect2()

func set_polygon(pts_array: Array) -> void:
	polygon_points.clear()
	if pts_array.is_empty():
		return
		
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for pt in pts_array:
		if typeof(pt) == TYPE_ARRAY and pt.size() >= 2:
			var v := Vector2(float(pt[0]), float(pt[1]))
			polygon_points.append(v)
			min_p.x = min(min_p.x, v.x)
			min_p.y = min(min_p.y, v.y)
			max_p.x = max(max_p.x, v.x)
			max_p.y = max(max_p.y, v.y)
	bounds = Rect2(min_p, max_p - min_p)

func is_point_inside(point: Vector3) -> bool:
	if polygon_points.size() < 3:
		return false
	var p2 := Vector2(point.x, point.z)
	# 1차 BBox 빠른 배제 (O(1))
	if not bounds.has_point(p2):
		return false
	# 2차 정밀 점-다각형 판정
	return Geometry2D.is_point_in_polygon(p2, polygon_points)

func get_localized_name(lang: String) -> String:
	return name_ko if lang == "ko" else name_en

func get_admin_hierarchy_label() -> String:
	var labels := PackedStringArray()
	for item in admin_hierarchy:
		labels.append(str(item))
	return " > ".join(labels)
