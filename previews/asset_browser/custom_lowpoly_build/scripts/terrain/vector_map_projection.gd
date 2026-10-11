extends RefCounted
## 공유 원본 벡터를 현재 지도 BBox로 투영한다. 저장된 원본은 수정하지 않는다.

static func apply(data: Dictionary, source: Dictionary, target) -> void:
	var source_size: float = source.world_size_meters
	var sx: float = target.world_size_meters / source_size * (float(source.bbox.east) - float(source.bbox.west)) / (target.bbox_east - target.bbox_west)
	var sz: float = target.world_size_meters / source_size * (float(source.bbox.north) - float(source.bbox.south)) / (target.bbox_north - target.bbox_south)
	var offset: Vector2 = Vector2(((float(source.bbox.west) + float(source.bbox.east)) / 2 - target.bbox_west) / (target.bbox_east - target.bbox_west) - 0.5,
		(target.bbox_north - (float(source.bbox.north) + float(source.bbox.south)) / 2) / (target.bbox_north - target.bbox_south) - 0.5) * target.world_size_meters
	# 같은 원본 범위는 재투영하지 않아 좌표와 기존 고도 속성을 보존한다.
	if is_equal_approx(sx, 1.0) and is_equal_approx(sz, 1.0) and offset.length() < 0.001:
		return
	for road in data.get("roads", []):
		road["projected_source"] = true
		for p in road.get("points", []):
			p[0] = float(p[0]) * sx + offset.x
			p[2] = float(p[2]) * sz + offset.y
		road["width"] = float(road.get("width", 8)) * sqrt(sx * sz)
	for building in data.get("buildings", []):
		if building.has("center"):
			building.center[0] = float(building.center[0]) * sx + offset.x
			building.center[2] = float(building.center[2]) * sz + offset.y
		for p in building.get("polygon", []):
			p[0] = float(p[0]) * sx + offset.x
			p[1] = float(p[1]) * sz + offset.y
		if building.has("size"):
			building.size[0] = float(building.size[0]) * sx
			building.size[2] = float(building.size[2]) * sz
	for breakwater in data.get("breakwaters", []):
		for p in breakwater.get("points", []):
			p[0] = float(p[0]) * sx + offset.x
			p[2] = float(p[2]) * sz + offset.y
