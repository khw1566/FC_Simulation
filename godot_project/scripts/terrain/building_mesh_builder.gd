extends RefCounted
class_name BuildingMeshBuilder

## 건물(폴리곤 돌출 빌딩 & 박스 빌딩) 3D 지오메트리 빌더 (대형/소형 계층 분리 & 높이 복원 & 지반 밀착)

## 대형 건물 기준: 바닥 스팬 >= 16m 또는 면적 >= 120㎡ 또는 높이 >= 18m
const MAJOR_SPAN_THRESHOLD: float = 16.0
const MAJOR_HEIGHT_THRESHOLD: float = 18.0
## 인덱스 없는 삼각형 목록(SurfaceTool 기본 출력)의 정점 배열을 보관하는 메타 키
const COLLISION_FACES_META := "collision_faces"
const CampusPolicy = preload("res://scripts/terrain/campus_building_policy.gd")
const CampusArchitecture = preload("res://scripts/terrain/campus_architecture_builder.gd")

static func build_chunk_buildings_mesh(chunk_buildings: Array, chunk_node: Node3D, mat: Material, sample_ground: Callable) -> void:
	apply_arrays(compute_arrays(chunk_buildings, sample_ground), chunk_node, mat, sample_ground)

## 메시 배열만 계산한다. 노드와 렌더링 자원을 만들지 않으므로 작업 스레드에서 실행할 수 있다.
## 캠퍼스 건축 상세는 노드를 만들기 때문에 작업 목록으로 돌려주고 apply_arrays()에서 처리한다.
static func compute_arrays(chunk_buildings: Array, sample_ground: Callable) -> Dictionary:
	var result := {"major": [], "minor": [], "campus": []}
	var major_st := SurfaceTool.new()
	major_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var major_count: int = 0

	var minor_st := SurfaceTool.new()
	minor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var minor_count: int = 0

	for b in chunk_buildings:
		var poly_arr: Array = b.get("polygon", [])
		if b.has("round"):
			poly_arr = _round_polygon(b.round)
		var base_y: float = float(b.get("base_y", 0.0))
		var height: float = float(b.get("height", 10.0))
		var center_arr: Array = b.get("center", [0, 0, 0])
		var size_arr: Array = b.get("size", [10, 10, 10])

		var cx: float = float(center_arr[0])
		var cz: float = float(center_arr[2])
		if poly_arr.size() >= 3:
			cx = 0.0; cz = 0.0
			for p in poly_arr:
				if p is Array and p.size() >= 2:
					cx += float(p[0]); cz += float(p[1])
			cx /= float(poly_arr.size()); cz /= float(poly_arr.size())

		if poly_arr.size() >= 3:
			var pts_2d: Array[Vector2] = []
			for p in poly_arr:
				if p is Array and p.size() >= 2:
					pts_2d.append(Vector2(float(p[0]), float(p[1])))

			if pts_2d.size() > 3 and pts_2d[0].distance_to(pts_2d[pts_2d.size() - 1]) < 0.01:
				pts_2d.pop_back()

			if pts_2d.size() >= 3:
				var terr_center_y: float = sample_ground.call(cx, cz, base_y)
				var actual_base_y: float = terr_center_y if terr_center_y > -90.0 else base_y
				if b.has("height_source"):
					for pt in pts_2d:
						actual_base_y = maxf(actual_base_y, float(sample_ground.call(pt.x, pt.y, base_y)))
				if CampusPolicy.is_campus_candidate(b):
					for pt in pts_2d:
						actual_base_y = maxf(actual_base_y, float(sample_ground.call(pt.x, pt.y, base_y)))
					for ring in Geometry2D.offset_polygon(PackedVector2Array(pts_2d), 3.0):
						for pt in ring:
							actual_base_y = maxf(actual_base_y, float(sample_ground.call(pt.x,pt.y,base_y)))
					actual_base_y += 0.12

				# 바닥 바운딩 계산
				var min_pt := pts_2d[0]; var max_pt := pts_2d[0]
				for pt in pts_2d:
					min_pt.x = minf(min_pt.x, pt.x); min_pt.y = minf(min_pt.y, pt.y)
					max_pt.x = maxf(max_pt.x, pt.x); max_pt.y = maxf(max_pt.y, pt.y)
				var span_x: float = max_pt.x - min_pt.x
				var span_z: float = max_pt.y - min_pt.y
				var max_span: float = maxf(span_x, span_z)

				# 높이 복원 휴리스틱
				var eff_height: float = height
				if eff_height <= 4.0 and not b.has("height_source") and not CampusPolicy.preserve_height(b):
					if max_span >= 30.0:
						eff_height = clampf(max_span * 0.9, 42.0, 65.0)
					elif max_span >= 16.0:
						eff_height = clampf(max_span * 0.8, 14.0, 22.0)
					else:
						eff_height = 8.5

				# 대형/소형 건물 분류 (고고도/원경 컬링용)
				var is_major: bool = (max_span >= MAJOR_SPAN_THRESHOLD or eff_height >= MAJOR_HEIGHT_THRESHOLD or (span_x * span_z) >= 140.0)
				var target_st := major_st if is_major else minor_st

				var roof_y: float = actual_base_y + eff_height
				if CampusPolicy.is_campus_candidate(b):
					result.campus.append([PackedVector2Array(pts_2d), actual_base_y, roof_y])
				var n_pts: int = pts_2d.size()

				var vert_base_ys: Array[float] = []
				for pt in pts_2d:
					var terr_y: float = sample_ground.call(pt.x, pt.y, actual_base_y)
					var grounded_y: float = minf(actual_base_y, terr_y) - 1.5
					vert_base_ys.append(grounded_y)

				# 벽면 사각형
				for i in range(n_pts):
					var p_curr: Vector2 = pts_2d[i]
					var p_next: Vector2 = pts_2d[(i + 1) % n_pts]
					var b0 := Vector3(p_curr.x, vert_base_ys[i], p_curr.y)
					var b1 := Vector3(p_next.x, vert_base_ys[(i + 1) % n_pts], p_next.y)
					var t1 := Vector3(p_next.x, roof_y, p_next.y)
					var t0 := Vector3(p_curr.x, roof_y, p_curr.y)
					var edge_dir := (b1 - b0).normalized()
					var wall_norm := Vector3(-edge_dir.z, 0.0, edge_dir.x)
					_add_quad(target_st, b0, b1, t1, t0, wall_norm)

				# 지붕 폴리곤 삼각화
				var packed_2d := PackedVector2Array(pts_2d)
				var tri_indices := Geometry2D.triangulate_polygon(packed_2d)
				if b.has("roof_triangles"):
					preload("res://scripts/terrain/building_courtyard_builder.gd").build(target_st, b, roof_y, actual_base_y, sample_ground)
				elif not tri_indices.is_empty():
					var is_cw: bool = Geometry2D.is_polygon_clockwise(packed_2d)
					for t in range(0, tri_indices.size(), 3):
						var i0: int = tri_indices[t]
						var i1: int = tri_indices[t + (1 if is_cw else 2)]
						var i2: int = tri_indices[t + (2 if is_cw else 1)]
						target_st.set_normal(Vector3.UP)
						target_st.set_uv(Vector2(pts_2d[i0].x * 0.05, pts_2d[i0].y * 0.05))
						target_st.add_vertex(Vector3(pts_2d[i0].x, roof_y, pts_2d[i0].y))
						target_st.set_uv(Vector2(pts_2d[i1].x * 0.05, pts_2d[i1].y * 0.05))
						target_st.add_vertex(Vector3(pts_2d[i1].x, roof_y, pts_2d[i1].y))
						target_st.set_uv(Vector2(pts_2d[i2].x * 0.05, pts_2d[i2].y * 0.05))
						target_st.add_vertex(Vector3(pts_2d[i2].x, roof_y, pts_2d[i2].y))
				else:
					var center_x: float = 0.0; var center_z: float = 0.0
					for pt in pts_2d:
						center_x += pt.x; center_z += pt.y
					var v_center := Vector3(center_x / float(n_pts), roof_y, center_z / float(n_pts))
					for i in range(n_pts):
						var p_curr: Vector2 = pts_2d[i]
						var p_next: Vector2 = pts_2d[(i + 1) % n_pts]
						target_st.set_normal(Vector3.UP)
						target_st.set_uv(Vector2(v_center.x * 0.05, v_center.z * 0.05))
						target_st.add_vertex(v_center)
						target_st.set_uv(Vector2(p_curr.x * 0.05, p_curr.y * 0.05))
						target_st.add_vertex(Vector3(p_curr.x, roof_y, p_curr.y))
						target_st.set_uv(Vector2(p_next.x * 0.05, p_next.y * 0.05))
						target_st.add_vertex(Vector3(p_next.x, roof_y, p_next.y))

				if is_major:
					major_count += 1
					if major_count >= 1200:
						_commit_arrays(major_st, result.major)
						major_count = 0
				else:
					minor_count += 1
					if minor_count >= 1200:
						_commit_arrays(minor_st, result.minor)
						minor_count = 0
		else:
			if center_arr.size() < 3 or size_arr.size() < 3:
				continue
			var cy: float = float(center_arr[1])
			var sx: float = float(size_arr[0]) * 0.5
			var sy: float = float(size_arr[1])
			var sz: float = float(size_arr[2]) * 0.5
			var terr_center_y: float = sample_ground.call(cx, cz, cy)
			var actual_cy: float = terr_center_y if terr_center_y > -90.0 else cy
			var grounded_box_bottom: float = actual_cy - 1.5
			var preserve_height: bool = b.has("height_source") or CampusPolicy.preserve_height(b)
			var box_height: float = height if preserve_height else (sy if sy > 4.0 else (45.0 if maxf(sx, sz) >= 15.0 else 9.0))
			var box_top: float = actual_cy + box_height

			var is_major_box: bool = (maxf(sx, sz) * 2.0 >= MAJOR_SPAN_THRESHOLD or (box_top - grounded_box_bottom) >= MAJOR_HEIGHT_THRESHOLD)
			var box_st := major_st if is_major_box else minor_st

			var p0 := Vector3(cx - sx, grounded_box_bottom, cz - sz)
			var p1 := Vector3(cx + sx, grounded_box_bottom, cz - sz)
			var p2 := Vector3(cx + sx, grounded_box_bottom, cz + sz)
			var p3 := Vector3(cx - sx, grounded_box_bottom, cz + sz)
			var p4 := Vector3(cx - sx, box_top, cz - sz)
			var p5 := Vector3(cx + sx, box_top, cz - sz)
			var p6 := Vector3(cx + sx, box_top, cz + sz)
			var p7 := Vector3(cx - sx, box_top, cz + sz)

			_add_quad(box_st, p7, p6, p5, p4, Vector3.UP)
			_add_quad(box_st, p0, p1, p5, p4, Vector3.FORWARD)
			_add_quad(box_st, p1, p2, p6, p5, Vector3.RIGHT)
			_add_quad(box_st, p2, p3, p7, p6, Vector3.BACK)
			_add_quad(box_st, p3, p0, p4, p7, Vector3.LEFT)

			if is_major_box:
				major_count += 1
				if major_count >= 1200:
					_commit_arrays(major_st, result.major)
					major_count = 0
			else:
				minor_count += 1
				if minor_count >= 1200:
					_commit_arrays(minor_st, result.minor)
					minor_count = 0

	if major_count > 0:
		_commit_arrays(major_st, result.major)
	if minor_count > 0:
		_commit_arrays(minor_st, result.minor)
	return result

## 스트림 최적화에서 [중심x, 중심z, 반경x, 반경z, 회전(도)]로 저장한 곡면 건물을
## 둘레 약 5m마다 꼭짓점을 두는 다각형으로 복원한다.
static func _round_polygon(spec: Array) -> Array:
	var rx := float(spec[2])
	var rz := float(spec[3])
	var perimeter := PI * (3.0 * (rx + rz) - sqrt((3.0 * rx + rz) * (rx + 3.0 * rz)))
	var segments := clampi(ceili(perimeter / 5.0), 12, 32)
	var basis := Transform2D(deg_to_rad(float(spec[4])), Vector2(float(spec[0]), float(spec[1])))
	var points: Array = []
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var p := basis * Vector2(rx * cos(angle), rz * sin(angle))
		points.append([p.x, p.y])
	return points

static func _commit_arrays(st: SurfaceTool, target: Array) -> void:
	target.append(st.commit_to_arrays())
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

## 계산된 배열로 대형/소형 건물 노드를 만든다. 메인 스레드에서 호출한다.
static func apply_arrays(result: Dictionary, chunk_node: Node3D, mat: Material, sample_ground: Callable) -> void:
	var major_container := Node3D.new()
	major_container.name = "MajorBuildings"
	chunk_node.add_child(major_container)
	var minor_container := Node3D.new()
	minor_container.name = "MinorBuildings"
	chunk_node.add_child(minor_container)
	for job in result.campus:
		CampusArchitecture.build(major_container, job[0], job[1], job[2], sample_ground)
	for pair in [[result.major, major_container], [result.minor, minor_container]]:
		for arrays in pair[0]:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			# 충돌 형상은 이 삼각형 정점으로 만든다. 렌더링 메시를 다시 읽으면 GPU 동기화로 프레임이 멈춘다.
			mi.set_meta(COLLISION_FACES_META, arrays[Mesh.ARRAY_VERTEX])
			pair[1].add_child(mi)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)

