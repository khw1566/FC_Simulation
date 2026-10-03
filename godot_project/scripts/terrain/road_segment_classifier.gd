extends RefCounted
class_name RoadSegmentClassifier

static func tag_enabled(road: Dictionary, key: String) -> bool:
	var value = road.get(key, road.get("is_" + key, false))
	if value is String:
		return value.to_lower() in ["yes", "true", "1", "viaduct", "building_passage"]
	return bool(value)

# 정점이 아닌 선분 단위로 분류하여 경계점은 인접 구간에서 공유한다.
static func classify(road: Dictionary, points: Array[Vector3], water: Array[float]) -> Array[int]:
	var types: Array[int] = []
	types.resize(maxi(0, points.size() - 1))
	types.fill(0)
	if tag_enabled(road, "tunnel"):
		types.fill(2)
		return types
	if tag_enabled(road, "bridge"):
		types.fill(1)
		return types
	if road.get("structure_tags_verified", false):
		return types
	var first: int = 0
	while first < types.size():
		if minf(water[first], water[first + 1]) < 0.65:
			first += 1
			continue
		var end: int = first
		var length: float = 0
		while end < types.size() and minf(water[end], water[end + 1]) >= 0.65:
			length += Vector2(points[end].x, points[end].z).distance_to(Vector2(points[end + 1].x, points[end + 1].z))
			end += 1
		# 단독 수계 픽셀·해안선 오차를 교량으로 확장하지 않는다.
		var bank_before: bool = first > 0 and water[first - 1] < 0.3
		var bank_after: bool = end + 1 < water.size() and water[end + 1] < 0.3
		if length >= 24 and bank_before and bank_after:
			for i in range(first - 1, mini(end + 1, types.size())):
				types[i] = 1
		first = end
	return types

static func geometry_key(road: Dictionary) -> String:
	var forward := PackedStringArray()
	for p in road.get("points", []):
		if p is Array and p.size() >= 3:
			forward.append("%.2f,%.2f,%.2f" % [float(p[0]), float(p[1]), float(p[2])])
	var backward := forward.duplicate()
	backward.reverse()
	var a := ";".join(forward)
	var b := ";".join(backward)
	return "%s|%s|%s|%s|%.2f" % [a if a < b else b, str(road.get("layer", 0)), str(tag_enabled(road, "bridge")), str(tag_enabled(road, "tunnel")), float(road.get("width", 8))]
