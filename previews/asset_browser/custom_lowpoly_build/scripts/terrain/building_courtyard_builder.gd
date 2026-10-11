extends RefCounted
## 전처리된 제약 삼각분할과 중정 내벽을 생성한다.
static func build(surface: SurfaceTool, building: Dictionary, roof_y: float, floor_y: float, sample_ground: Callable) -> void:
	for triangle in building.get("roof_triangles", []):
		var points := PackedVector2Array()
		for point in triangle:
			points.append(Vector2(float(point[0]), float(point[1])))
		if points.size() != 3:
			continue
		if not Geometry2D.is_polygon_clockwise(points):
			points.reverse()
		for point in points:
			surface.set_normal(Vector3.UP)
			surface.set_uv(point * 0.05)
			surface.add_vertex(Vector3(point.x, roof_y, point.y))
	for hole in building.get("holes", []):
		for i in range(hole.size()):
			var a := Vector2(float(hole[i][0]), float(hole[i][1]))
			var b := Vector2(float(hole[(i+1)%hole.size()][0]), float(hole[(i+1)%hole.size()][1]))
			var bottom_a: float = minf(floor_y, float(sample_ground.call(a.x, a.y, floor_y))) - 1.5
			var bottom_b: float = minf(floor_y, float(sample_ground.call(b.x, b.y, floor_y))) - 1.5
			var vertices := [Vector3(a.x,bottom_a,a.y),Vector3(b.x,bottom_b,b.y),Vector3(b.x,roof_y,b.y),Vector3(a.x,roof_y,a.y)]
			var normal := Vector3(b.y-a.y,0,a.x-b.x).normalized()
			for index in [0,1,2,0,2,3]:
				surface.set_normal(normal)
				surface.set_uv(Vector2(vertices[index].x, vertices[index].y) * 0.05)
				surface.add_vertex(vertices[index])
