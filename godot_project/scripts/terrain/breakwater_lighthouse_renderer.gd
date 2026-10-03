extends Node3D
class_name BreakwaterLighthouseRenderer

## 방파제(Breakwater) 콘크리트 구조물 및 끝단 등대(Lighthouse) 3D 메시 생성기
## buildings_and_roads.json의 breakwaters 배열을 읽어 프로시저럴 메시로 렌더링

var breakwater_material: StandardMaterial3D
var lighthouse_base_material: StandardMaterial3D
var lighthouse_lantern_material: StandardMaterial3D
var terrain_manager: Node3D

func _ready() -> void:
	_init_materials()

func _init_materials() -> void:
	# 방파제 콘크리트
	breakwater_material = StandardMaterial3D.new()
	breakwater_material.albedo_color = Color(0.55, 0.53, 0.50, 1.0)
	breakwater_material.roughness = 0.95
	breakwater_material.metallic_specular = 0.05
	breakwater_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 등대 기둥 (흰색 콘크리트)
	lighthouse_base_material = StandardMaterial3D.new()
	lighthouse_base_material.albedo_color = Color(0.95, 0.95, 0.92, 1.0)
	lighthouse_base_material.roughness = 0.7
	lighthouse_base_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 등대 랜턴실 (빨간색 또는 녹색)
	lighthouse_lantern_material = StandardMaterial3D.new()
	lighthouse_lantern_material.albedo_color = Color(0.85, 0.15, 0.1, 1.0)
	lighthouse_lantern_material.roughness = 0.3
	lighthouse_lantern_material.metallic = 0.4
	lighthouse_lantern_material.emission_enabled = true
	lighthouse_lantern_material.emission = Color(1.0, 0.3, 0.2, 1.0)
	lighthouse_lantern_material.emission_energy_multiplier = 3.0
	lighthouse_lantern_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func render_breakwaters(breakwaters_data: Array) -> void:
	if breakwaters_data.is_empty():
		return

	var container := Node3D.new()
	container.name = "BreakwatersContainer"
	add_child(container)

	var count: int = 0
	for bw in breakwaters_data:
		var pts_raw: Array = bw.get("points", [])
		if pts_raw.size() < 2:
			continue

		var pts: Array[Vector3] = []
		for p in pts_raw:
			if p is Array and p.size() >= 3:
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))

		if pts.size() < 2:
			continue

		# 방파제 구조물 메시 생성
		var bw_node := _build_breakwater_mesh(pts, float(bw.get("width_m", 8.0)))
		if bw_node:
			bw_node.name = "Breakwater_%d" % bw.get("id", count)
			container.add_child(bw_node)

		# 끝단 등대 생성
		if bool(bw.get("has_lighthouse", false)):
			var lh := _build_lighthouse(pts[pts.size() - 1], pts[pts.size() - 2])
			if lh:
				lh.name = "Lighthouse_%d" % bw.get("id", count)
				container.add_child(lh)

		count += 1

	print("[BreakwaterRenderer] Rendered %d breakwaters with lighthouses." % count)

func _build_breakwater_mesh(pts: Array[Vector3], bw_width: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var wall_height: float = 4.5
	var half_w: float = clampf(bw_width * 0.5, 2.5, 12.0)

	# 지형 고도 샘플링 함수 가져오기
	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]

		var dir := (p1 - p0).normalized()
		var side := dir.cross(Vector3.UP).normalized() * half_w

		# 기저 고도: 해수면 또는 지형 위 0.3m 중 높은 값
		var base_y0: float = _sample_terrain_y(p0.x, p0.z, p0.y)
		var base_y1: float = _sample_terrain_y(p1.x, p1.z, p1.y)

		var a := Vector3(p0.x - side.x, base_y0, p0.z - side.z)
		var b := Vector3(p0.x + side.x, base_y0, p0.z + side.z)
		var c := Vector3(p1.x + side.x, base_y1, p1.z + side.z)
		var d := Vector3(p1.x - side.x, base_y1, p1.z - side.z)

		var at := Vector3(a.x, base_y0 + wall_height, a.z)
		var bt := Vector3(b.x, base_y0 + wall_height, b.z)
		var ct := Vector3(c.x, base_y1 + wall_height, c.z)
		var dt := Vector3(d.x, base_y1 + wall_height, d.z)

		# 상면 (방파제 상부 보도)
		_add_quad(st, at, bt, ct, dt, Vector3.UP)
		# 좌측면
		_add_quad(st, a, at, dt, d, -side.normalized())
		# 우측면
		_add_quad(st, bt, b, c, ct, side.normalized())
		# 하면 (해저 방향)
		var down_a := Vector3(a.x, base_y0 - 3.0, a.z)
		var down_b := Vector3(b.x, base_y0 - 3.0, b.z)
		var down_c := Vector3(c.x, base_y1 - 3.0, c.z)
		var down_d := Vector3(d.x, base_y1 - 3.0, d.z)
		_add_quad(st, a, d, down_d, down_a, -side.normalized())
		_add_quad(st, c, b, down_b, down_c, side.normalized())

	# 시점/종점 수직 마감벽
	if pts.size() >= 2:
		var dir_start := (pts[1] - pts[0]).normalized()
		var side_start := dir_start.cross(Vector3.UP).normalized() * half_w
		var by0 := _sample_terrain_y(pts[0].x, pts[0].z, pts[0].y)
		_add_end_wall(st, pts[0], side_start, by0, wall_height, -dir_start)

		var dir_end := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		var side_end := dir_end.cross(Vector3.UP).normalized() * half_w
		var byN := _sample_terrain_y(pts[pts.size() - 1].x, pts[pts.size() - 1].z, pts[pts.size() - 1].y)
		_add_end_wall(st, pts[pts.size() - 1], side_end, byN, wall_height, dir_end)

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = breakwater_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

func _build_lighthouse(pos: Vector3, prev_pos: Vector3) -> Node3D:
	var lh_root := Node3D.new()
	var base_y := _sample_terrain_y(pos.x, pos.z, pos.y) + 4.5

	# 1. 기둥 (원기둥 형태: 8각형 프리즘)
	var tower_h: float = 12.0
	var tower_r_bottom: float = 2.2
	var tower_r_top: float = 1.6
	var segments: int = 8

	var st_tower := SurfaceTool.new()
	st_tower.begin(Mesh.PRIMITIVE_TRIANGLES)

	for s in range(segments):
		var a0: float = TAU * float(s) / float(segments)
		var a1: float = TAU * float(s + 1) / float(segments)

		var bx0 := pos.x + cos(a0) * tower_r_bottom
		var bz0 := pos.z + sin(a0) * tower_r_bottom
		var bx1 := pos.x + cos(a1) * tower_r_bottom
		var bz1 := pos.z + sin(a1) * tower_r_bottom
		var tx0 := pos.x + cos(a0) * tower_r_top
		var tz0 := pos.z + sin(a0) * tower_r_top
		var tx1 := pos.x + cos(a1) * tower_r_top
		var tz1 := pos.z + sin(a1) * tower_r_top

		var va := Vector3(bx0, base_y, bz0)
		var vb := Vector3(bx1, base_y, bz1)
		var vc := Vector3(tx1, base_y + tower_h, tz1)
		var vd := Vector3(tx0, base_y + tower_h, tz0)

		var n := (Vector3(cos(a0 + (a1 - a0) * 0.5), 0, sin(a0 + (a1 - a0) * 0.5))).normalized()
		_add_quad(st_tower, va, vb, vc, vd, n)

	st_tower.generate_normals()
	var tower_mesh := st_tower.commit()
	var tower_mi := MeshInstance3D.new()
	tower_mi.mesh = tower_mesh
	tower_mi.material_override = lighthouse_base_material
	tower_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	lh_root.add_child(tower_mi)

	# 2. 랜턴실 (상부 원기둥 + 유리 돔)
	var lantern_y: float = base_y + tower_h
	var lantern_h: float = 3.0
	var lantern_r: float = 2.0

	var st_lantern := SurfaceTool.new()
	st_lantern.begin(Mesh.PRIMITIVE_TRIANGLES)

	for s in range(segments):
		var a0: float = TAU * float(s) / float(segments)
		var a1: float = TAU * float(s + 1) / float(segments)

		var x0 := pos.x + cos(a0) * lantern_r
		var z0 := pos.z + sin(a0) * lantern_r
		var x1 := pos.x + cos(a1) * lantern_r
		var z1 := pos.z + sin(a1) * lantern_r

		var va := Vector3(x0, lantern_y, z0)
		var vb := Vector3(x1, lantern_y, z1)
		var vc := Vector3(x1, lantern_y + lantern_h, z1)
		var vd := Vector3(x0, lantern_y + lantern_h, z0)

		var n := (Vector3(cos(a0 + (a1 - a0) * 0.5), 0, sin(a0 + (a1 - a0) * 0.5))).normalized()
		_add_quad(st_lantern, va, vb, vc, vd, n)

	# 랜턴실 지붕 (원추형)
	var roof_y: float = lantern_y + lantern_h
	var roof_peak := Vector3(pos.x, roof_y + 2.0, pos.z)
	for s in range(segments):
		var a0: float = TAU * float(s) / float(segments)
		var a1: float = TAU * float(s + 1) / float(segments)
		var rx0 := pos.x + cos(a0) * lantern_r
		var rz0 := pos.z + sin(a0) * lantern_r
		var rx1 := pos.x + cos(a1) * lantern_r
		var rz1 := pos.z + sin(a1) * lantern_r

		st_lantern.set_normal(Vector3.UP)
		st_lantern.set_uv(Vector2(0.5, 0.0)); st_lantern.add_vertex(roof_peak)
		st_lantern.set_uv(Vector2(0.0, 1.0)); st_lantern.add_vertex(Vector3(rx0, roof_y, rz0))
		st_lantern.set_uv(Vector2(1.0, 1.0)); st_lantern.add_vertex(Vector3(rx1, roof_y, rz1))

	st_lantern.generate_normals()
	var lantern_mesh := st_lantern.commit()
	var lantern_mi := MeshInstance3D.new()
	lantern_mi.mesh = lantern_mesh
	lantern_mi.material_override = lighthouse_lantern_material
	lantern_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	lh_root.add_child(lantern_mi)

	# 3. 등대 발광 옴니라이트
	var light := OmniLight3D.new()
	light.position = Vector3(pos.x, lantern_y + lantern_h * 0.5, pos.z)
	light.light_color = Color(1.0, 0.95, 0.8)
	light.light_energy = 5.0
	light.omni_range = 200.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	lh_root.add_child(light)

	return lh_root

func _add_end_wall(st: SurfaceTool, center: Vector3, side: Vector3, base_y: float, wall_h: float, face_dir: Vector3) -> void:
	var a := Vector3(center.x - side.x, base_y - 3.0, center.z - side.z)
	var b := Vector3(center.x + side.x, base_y - 3.0, center.z + side.z)
	var c := Vector3(center.x + side.x, base_y + wall_h, center.z + side.z)
	var d := Vector3(center.x - side.x, base_y + wall_h, center.z - side.z)
	_add_quad(st, a, b, c, d, face_dir)

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)

func _sample_terrain_y(wx: float, wz: float, fallback: float) -> float:
	if terrain_manager and terrain_manager.has_method("get_terrain_elevation"):
		return maxf(terrain_manager.get_terrain_elevation(wx, wz), 0.3)
	return maxf(fallback, 0.3)
