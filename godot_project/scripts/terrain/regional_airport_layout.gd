extends RefCounted
## 공항 모델은 동쪽 +X, 남쪽 +Z의 실제 미터 좌표를 사용한다.

static func frame(spec: Dictionary, meta: Dictionary) -> Transform3D:
	var lat: float = spec.anchor.lat
	var lon: float = spec.anchor.lon
	var size: float = meta.world_size_meters
	var sx := size / (float(meta.bbox.east) - float(meta.bbox.west)) / (111320.0 * cos(deg_to_rad(lat)))
	var sz := size / (float(meta.bbox.north) - float(meta.bbox.south)) / 111320.0
	var center := Vector3(((lon - float(meta.bbox.west)) / (float(meta.bbox.east) - float(meta.bbox.west)) - 0.5) * size,
		float(spec.elevation_m), ((float(meta.bbox.north) - lat) / (float(meta.bbox.north) - float(meta.bbox.south)) - 0.5) * size)
	return Transform3D(Basis.from_scale(Vector3(sx, 1, sz)), center)

static func in_map(spec: Dictionary, meta: Dictionary) -> bool:
	return float(spec.anchor.lat) >= float(meta.bbox.south) and float(spec.anchor.lat) <= float(meta.bbox.north) and float(spec.anchor.lon) >= float(meta.bbox.west) and float(spec.anchor.lon) <= float(meta.bbox.east)

static func bounds(spec: Dictionary) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for runway in spec.runways:
		for p in [runway.start, runway.end]:
			var point := Vector2(p[0], p[1])
			low = low.min(point - Vector2.ONE * (float(runway.width_m) / 2 + 30))
			high = high.max(point + Vector2.ONE * (float(runway.width_m) / 2 + 30))
	for feature in spec.features:
		for p in feature.points:
			var point := Vector2(p[0], p[1])
			low = low.min(point - Vector2.ONE * 20)
			high = high.max(point + Vector2.ONE * 20)
	return Rect2(low, high - low).grow(300)
