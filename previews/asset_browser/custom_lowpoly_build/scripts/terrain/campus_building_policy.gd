extends RefCounted
class_name CampusBuildingPolicy

## 기존 명칭과 주소에 따른 후보 판별이며 지적 경계를 확정하지 않는다.
static func is_campus_candidate(building: Dictionary) -> bool:
	if building.get("_campus_art_candidate", false):
		return true
	var label := str(building.get("name", "")).strip_edges()
	return label.contains("울산대학교") or label.contains("울산과학대") or label == "대학로 57" or label == "대학로 93"

static func preserve_height(building: Dictionary) -> bool:
	return is_campus_candidate(building) and float(building.get("height", 0.0)) > 0.0

## 서부캠퍼스 영상에서 판독한 근사 작업 구역. 울산 지도에만 적용한다.
static func mark_imagery_candidates(buildings: Array) -> void:
	var college_zone := PackedVector2Array([Vector2(-620,-850),Vector2(-210,-850),Vector2(-210,-600),Vector2(-380,-560),Vector2(-610,-600)])
	for building in buildings:
		var polygon: Array = building.get("polygon", [])
		if polygon.size() < 3:
			continue
		var center := Vector2.ZERO
		for point in polygon:
			center += Vector2(float(point[0]),float(point[1]))
		center /= polygon.size()
		if Geometry2D.is_point_in_polygon(center, college_zone):
			building["_campus_art_candidate"] = true
