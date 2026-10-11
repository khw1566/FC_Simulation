extends RefCounted
class_name IndustrialBuildingSuppression

## 절차 생성 공단 구역 안의 범용 건물을 생성하지 않는다.
## 공단 표시 설정이 꺼진 상태로 지도를 시작하면 범용 건물을 그대로 둔다.
const PATH := "res://assets/generated/industrial_zones/ulsan_metro_80km/building_suppression.json"
var _zones: Array[Dictionary] = []

func configure(map_id: String) -> void:
	_zones.clear()
	if map_id != "ulsan_metro_80km" or not FileAccess.file_exists(PATH):
		return
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null("UserSettingsService") if tree else null
	if settings and not settings.industrial_zones_enabled:
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		return
	for zone in data.get("zones", []):
		var b: Array = zone.bounds
		var ring := PackedVector2Array()
		for p in zone.ring_xz:
			ring.append(Vector2(float(p[0]), float(p[1])))
		_zones.append({"rect": Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1]), "ring": ring})

func replaces(world_x: float, world_z: float) -> bool:
	var point := Vector2(world_x, world_z)
	for zone in _zones:
		if zone.rect.has_point(point) and Geometry2D.is_point_in_polygon(point, zone.ring):
			return true
	return false
