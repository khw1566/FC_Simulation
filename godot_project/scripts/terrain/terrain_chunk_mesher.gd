extends RefCounted
class_name TerrainChunkMesher

## 지형 청크 LOD 메시 배열과 충돌면을 계산한다.
## 장면 트리·렌더링 서버에 접근하지 않으므로 작업 스레드에서 실행할 수 있다.

static func compute(request: Dictionary) -> Dictionary:
	var image: Image = request.image
	var grid_res: int = request.grid_res
	var size: float = request.size
	var center: Vector3 = request.center
	var elev_min: float = request.elev_min
	var elev_range: float = request.elev_max - request.elev_min
	var grader: RefCounted = request.grader
	var step := size / float(grid_res)
	var half_size := size * 0.5
	var img_w := image.get_width()
	var img_h := image.get_height()
	var railway_cells := {}
	if grader:
		railway_cells = grader.cells(Vector2(center.x - half_size, center.z - half_size), size, grid_res)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize((grid_res + 1) * (grid_res + 1))
	uvs.resize(vertices.size())
	for y in range(grid_res + 1):
		var v := float(y) / float(grid_res)
		for x in range(grid_res + 1):
			var u := float(x) / float(grid_res)
			var index := y * (grid_res + 1) + x
			vertices[index] = Vector3(float(x) * step - half_size, elev_min + sample_bilinear(image, u, v, img_w, img_h) * elev_range, float(y) * step - half_size)
			uvs[index] = Vector2(u, v)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(grid_res):
		for x in range(grid_res):
			var i0 := y * (grid_res + 1) + x
			var i1 := i0 + 1
			var i2 := (y + 1) * (grid_res + 1) + x
			var i3 := i2 + 1
			var segments: Array = railway_cells.get(Vector2i(x, y), [])
			if not segments.is_empty():
				grader.add_triangle(surface, vertices[i0], vertices[i1], vertices[i2], center, segments, size)
				grader.add_triangle(surface, vertices[i1], vertices[i3], vertices[i2], center, segments, size)
				continue
			for i in [i0, i1, i2, i1, i3, i2]:
				surface.set_uv(uvs[i])
				surface.add_vertex(vertices[i])
	surface.generate_normals()
	# 정점을 공유해 메인 스레드에서 업로드할 자료량을 줄인다.
	surface.index()
	var arrays := surface.commit_to_arrays()
	var result := {"arrays": arrays}
	if request.collision:
		# 삼각형 충돌체는 BVH 생성 중 물리 서버가 메인 스레드까지 멈추게 해 100ms 안팎의 끊김을 만든다.
		# 격자 높이 충돌체용 높이만 계산하고, 철도 절토 보정 높이를 격자점에 반영한다.
		var heights := PackedFloat32Array()
		heights.resize(vertices.size())
		for index in vertices.size():
			var vertex := vertices[index]
			heights[index] = grader.corrected_height(vertex + center) if grader else vertex.y
		result["heights"] = heights
		result["grid_res"] = grid_res
		result["step"] = step
	return result

static func sample_bilinear(image: Image, u: float, v: float, w: int, h: int) -> float:
	var fx: float = clampf(u * float(w - 1), 0.0, float(w - 1))
	var fy: float = clampf(v * float(h - 1), 0.0, float(h - 1))
	var x0: int = int(fx)
	var y0: int = int(fy)
	var x1: int = mini(x0 + 1, w - 1)
	var y1: int = mini(y0 + 1, h - 1)
	var raw_dx: float = fx - float(x0)
	var raw_dy: float = fy - float(y0)
	# 3차 에르미트 S-커브 가중치로 픽셀 격자 경계의 꺾임을 없앤다.
	var dx: float = raw_dx * raw_dx * (3.0 - 2.0 * raw_dx)
	var dy: float = raw_dy * raw_dy * (3.0 - 2.0 * raw_dy)
	var top := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, dx)
	var bottom := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, dx)
	return lerpf(top, bottom, dy)
