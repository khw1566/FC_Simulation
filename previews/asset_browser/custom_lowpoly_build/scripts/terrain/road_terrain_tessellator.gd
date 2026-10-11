extends RefCounted
class_name RoadTerrainTessellator

# 모든 LOD의 격자선/대각선이 LOD0 격자에 포함된다.
# 도로를 이 경계에서 자르면 셰이더 높이 보간이 실제 지형 삼각형과 일치한다.
static func add_quad(surface: SurfaceTool, corners: Array, step: Vector2, origin: Vector2) -> void:
	for triangle in [[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]]:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for p in triangle:
			var grid := (Vector2(p.x, p.z) - origin) / step
			low = low.min(grid)
			high = high.max(grid)
		for cy in range(int(floor(low.y)), int(floor(high.y)) + 1):
			for cx in range(int(floor(low.x)), int(floor(high.x)) + 1):
				var a := origin + Vector2(cx, cy) * step
				var b := a + Vector2(step.x, 0)
				var c := a + Vector2(0, step.y)
				var d := a + step
				for cell in [[a, b, c], [b, d, c]]:
					var polygon: Array = triangle.duplicate()
					for i in range(3):
						polygon = _clip(polygon, cell[i], cell[(i + 1) % 3])
					for i in range(1, polygon.size() - 1):
						if (polygon[i] - polygon[0]).cross(polygon[i + 1] - polygon[0]).length_squared() < 0.000001:
							continue
						for vertex in [polygon[0], polygon[i], polygon[i + 1]]:
							surface.set_normal(Vector3.UP)
							surface.set_uv2(Vector2.ZERO)
							surface.add_vertex(vertex)

static func split_edge(a: Vector3, b: Vector3, step: Vector2, origin: Vector2) -> Array[Vector3]:
	var from := (Vector2(a.x, a.z) - origin) / step
	var to := (Vector2(b.x, b.z) - origin) / step
	var cuts: Array[float] = [0.0, 1.0]
	for pair in [Vector2(from.x, to.x), Vector2(from.y, to.y), Vector2(from.x + from.y, to.x + to.y)]:
		if is_equal_approx(pair.x, pair.y):
			continue
		for boundary in range(int(ceil(minf(pair.x, pair.y))), int(floor(maxf(pair.x, pair.y))) + 1):
			var t: float = (boundary - pair.x) / (pair.y - pair.x)
			if t > 0.00001 and t < 0.99999:
				cuts.append(t)
	cuts.sort()
	var result: Array[Vector3] = []
	var previous: float = -1
	for t in cuts:
		if absf(t - previous) > 0.00001:
			result.append(a.lerp(b, t))
			previous = t
	return result

static func _clip(polygon: Array, a: Vector2, b: Vector2) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon[-1]
	var edge := b - a
	var previous_side: float = edge.cross(Vector2(previous.x, previous.z) - a)
	for current: Vector3 in polygon:
		var side: float = edge.cross(Vector2(current.x, current.z) - a)
		if (side >= 0) != (previous_side >= 0):
			var t := previous_side / (previous_side - side)
			result.append(previous.lerp(current, t))
		if side >= 0:
			result.append(current)
		previous = current
		previous_side = side
	return result
