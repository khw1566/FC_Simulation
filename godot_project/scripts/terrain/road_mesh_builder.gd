extends RefCounted
class_name RoadMeshBuilder

const TerrainTessellator = preload("res://scripts/terrain/road_terrain_tessellator.gd")

## 도로, 교량, 터널 3D 메시 지오메트리 빌더 (연속 마이터 리본 메쉬 & 급커브 파편화 방지)

## 도로 폴리라인을 곡률 적응형(Adaptive)으로 세분화: 커브길은 촘촘히 보간하고 직선은 간소화하여 최적화
static func subdivide_polyline(pts: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var n_raw := pts.size()
	if n_raw < 2:
		return result

	var p0_arr = pts[0]
	var prev := Vector3(float(p0_arr[0]), float(p0_arr[1]), float(p0_arr[2]))
	result.append(prev)

	for i in range(1, n_raw):
		var p_arr = pts[i]
		var curr := Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
		var seg_vec := curr - prev
		var dist := seg_vec.length()
		if Vector2(seg_vec.x, seg_vec.z).length_squared() < 0.0001:
			continue

		# 곡률 감지: 인접 세그먼트 간의 각도 변화량 검사
		var is_curved: bool = false
		if i < n_raw - 1:
			var next_arr = pts[i + 1]
			var next_pt := Vector3(float(next_arr[0]), float(next_arr[1]), float(next_arr[2]))
			var next_vec := next_pt - curr
			if dist > 0.01 and next_vec.length() > 0.01:
				var dot_val := seg_vec.normalized().dot(next_vec.normalized())
				if dot_val < 0.985: # 약 10도 이상 꺾인 커브
					is_curved = true

		var max_step := 10.0 if is_curved else 24.0
		if dist > max_step:
			var steps := int(ceil(dist / max_step))
			for s in range(1, steps):
				var t := float(s) / float(steps)
				result.append(prev.lerp(curr, t))
		result.append(curr)
		prev = curr

	return result

## 1. 지형 밀착 도로 (연속 마이터 리본 메쉬: 급커브 파편화/틈새 100% 제거 및 공유 버텍스 최적화)
static func build_surface_road(st: SurfaceTool, pts: Array[Vector3], ground_y: Array[float], width: float, sample_func: Callable, terrain_step: Vector2 = Vector2.ZERO, terrain_origin: Vector2 = Vector2.ZERO, clearance: float = 0.85, formed_ground: bool = false, context: Dictionary = {}) -> void:
	var n_pts := pts.size()
	if n_pts < 2:
		return

	var half_w: float = width * 0.5
	var skirt_depth: float = 2.6
	var elev_offset: float = clearance

	# 1. 정점별 진행 방향 및 마이터(이등분선) 횡단 벡터 계산
	var sides: Array[Vector3] = []
	sides.resize(n_pts)

	var seg_dirs: Array[Vector3] = []
	seg_dirs.resize(n_pts - 1)
	for i in range(n_pts - 1):
		var d := Vector3(pts[i + 1].x - pts[i].x, 0.0, pts[i + 1].z - pts[i].z)
		seg_dirs[i] = Vector3.FORWARD if d.is_zero_approx() else d.normalized()

	for i in range(n_pts):
		var tangent: Vector3
		var miter_scale: float = 1.0

		var d_prev := seg_dirs[maxi(0,i-1)]
		var d_next := seg_dirs[mini(n_pts-2,i)]
		if i == 0 and context.has("before"):
			d_prev = pts[0]-Vector3(context.before)
			d_prev.y = 0.0
			d_prev = d_prev.normalized()
		if i == n_pts-1 and context.has("after"):
			d_next = Vector3(context.after)-pts[-1]
			d_next.y = 0.0
			d_next = d_next.normalized()
		tangent = d_prev+d_next
		if tangent.is_zero_approx():
			tangent = d_prev
		else:
			tangent = tangent.normalized()
		var cos_half := d_prev.dot(tangent)
		miter_scale = clampf(1.0/maxf(cos_half,.5),1.0,1.8)

		var normal_side := tangent.cross(Vector3.UP).normalized()
		sides[i] = normal_side * (half_w * miter_scale)

	# 2. 정점별 좌우 좌표 및 수평 노반 안전고도 산출
	var left_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	left_pts.resize(n_pts)
	right_pts.resize(n_pts)

	for i in range(n_pts):
		var p := pts[i]
		var side := sides[i]
		var base_y := maxf(p.y, ground_y[i])

		var lx := p.x - side.x
		var lz := p.z - side.z
		var rx := p.x + side.x
		var rz := p.z + side.z

		var left_gy: float = sample_func.call(lx, lz, base_y)
		var right_gy: float = sample_func.call(rx, rz, base_y)
		var safe_y := maxf(base_y, maxf(ground_y[i], maxf(left_gy, right_gy))) + elev_offset

		left_pts[i] = Vector3(lx, safe_y, lz)
		right_pts[i] = Vector3(rx, safe_y, rz)

	# 3. 연속 리본 메쉬 생성 (인접 세그먼트가 동일 정점을 공유하여 틈새 및 파편화 원천 방지)
	for i in range(n_pts - 1):
		var a := left_pts[i]
		var b := right_pts[i]
		var c := right_pts[i + 1]
		var d := left_pts[i + 1]

		st.set_uv2(Vector2(1.0 if formed_ground else 0.0, 0.0))
		if terrain_step.x > 0 and terrain_step.y > 0:
			TerrainTessellator.add_quad(st, [a, b, c, d], terrain_step, terrain_origin, formed_ground)
		else:
			add_quad(st, a, b, c, d, Vector3.UP)

		var side_dir := sides[i].normalized()
		for pair in [[a, d, -side_dir], [c, b, side_dir]]:
			var edge: Array[Vector3] = [pair[0], pair[1]]
			if terrain_step.x > 0 and terrain_step.y > 0:
				edge = TerrainTessellator.split_edge(pair[0], pair[1], terrain_step, terrain_origin)
			for j in range(edge.size() - 1):
				_add_road_skirt(st, edge[j], edge[j + 1], skirt_depth, pair[2], formed_ground)

static func _add_road_skirt(st: SurfaceTool, a: Vector3, b: Vector3, depth: float, normal: Vector3, formed_ground: bool = false) -> void:
	var positions := [a, b, b + Vector3.DOWN * depth, a, b + Vector3.DOWN * depth, a + Vector3.DOWN * depth]
	for i in range(6):
		st.set_normal(normal)
		st.set_uv2(Vector2(1.0 if formed_ground else 0.0, -depth if i in [2, 4, 5] else 0.0))
		st.add_vertex(positions[i])
	st.set_uv2(Vector2.ZERO)

## 2. 범용 다리 (강/하천/수계 횡단 - 상판 슬래브 + 가드레일 + 하천 바닥까지 수직 교각)
static func build_universal_bridge(st: SurfaceTool, pts: Array[Vector3], ground_y: Array[float], width: float) -> void:
	var n_pts := pts.size()
	if n_pts < 2:
		return

	var half_w: float = width * 0.5
	var railing_h: float = 1.4
	var slab_thickness: float = 1.2
	var pier_interval_dist: float = 40.0
	var accumulated_dist: float = 0.0
	var distances: Array[float] = [0.0]
	for i in range(1, n_pts):
		distances.append(distances[-1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
	var total_length: float = distances[-1]
	if total_length < 0.01:
		return

	var start_elev: float = maxf(pts[0].y, ground_y[0]) + 1.2
	var end_elev: float = maxf(pts[n_pts - 1].y, ground_y[n_pts - 1]) + 1.2
	var sides: Array[Vector3] = []

	var deck_ys: Array[float] = []
	deck_ys.resize(n_pts)
	for i in range(n_pts):
		var t := distances[i] / total_length
		var linear_h := lerpf(start_elev, end_elev, t)
		var arch_h := sin(t * PI) * minf(1.5, total_length * 0.015)
		var target_h := maxf(linear_h + arch_h, pts[i].y + 1.2)
		target_h = maxf(target_h, ground_y[i] + 1.2)
		deck_ys[i] = target_h
		var prev := pts[i] - pts[maxi(0, i - 1)]
		var next := pts[mini(n_pts - 1, i + 1)] - pts[i]
		prev.y = 0
		next.y = 0
		if prev.is_zero_approx():
			prev = next
		if next.is_zero_approx():
			next = prev
		var tangent := prev.normalized() + next.normalized()
		if tangent.is_zero_approx():
			tangent = next.normalized()
		tangent = tangent.normalized()
		var miter := clampf(1.0 / maxf(0.55, tangent.dot(prev.normalized())), 1.0, 1.6)
		sides.append(tangent.cross(Vector3.UP).normalized() * half_w * miter)

	for i in range(n_pts - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var deck_y0: float = deck_ys[i]
		var deck_y1: float = deck_ys[i + 1]

		var p0_deck := Vector3(p0.x, deck_y0, p0.z)
		var p1_deck := Vector3(p1.x, deck_y1, p1.z)

		var dir := (p1_deck - p0_deck).normalized()
		var side := sides[i]

		var a := p0_deck - side
		var b := p0_deck + side
		var c := p1_deck + sides[i + 1]
		var d := p1_deck - sides[i + 1]

		add_quad(st, a, b, c, d, Vector3.UP)

		var down_v := Vector3.DOWN * slab_thickness
		add_quad(st, a + down_v, a, d, d + down_v, -side.normalized())
		add_quad(st, b, b + down_v, c + down_v, c, side.normalized())

		var up_r := Vector3.UP * railing_h
		add_quad(st, a, a + up_r, d + up_r, d, -side.normalized())
		add_quad(st, b + up_r, b, c, c + up_r, side.normalized())

		if i == 0:
			var abut_down := Vector3.DOWN * maxf(slab_thickness, deck_y0 - ground_y[0] + 1.0)
			add_quad(st, a + abut_down, b + abut_down, b, a, -dir)
		if i == n_pts - 2:
			var abut_down_end := Vector3.DOWN * maxf(slab_thickness, deck_y1 - ground_y[n_pts - 1] + 1.0)
			add_quad(st, c, d, d + abut_down_end, c + abut_down_end, dir)

		# 조각마다 첫 교각을 만들지 않고 누적 거리 40m마다 하나씩 만든다.
		accumulated_dist += Vector2(p1.x - p0.x, p1.z - p0.z).length()
		if accumulated_dist >= pier_interval_dist:
			accumulated_dist = fmod(accumulated_dist, pier_interval_dist)
			if distances[i + 1] < total_length - 12 and deck_y1 - ground_y[i + 1] > 2.0:
				build_bridge_pier(st, p1_deck - Vector3.UP * slab_thickness, ground_y[i + 1], clampf(width * 0.1, 0.6, 2.2))

## 교량 하부 수직 교각(Pillar/Pier) 4각 기둥 생성
static func build_bridge_pier(st: SurfaceTool, top_center: Vector3, bottom_y: float, pier_radius: float) -> void:
	var r := pier_radius
	var p0 := Vector3(top_center.x - r, top_center.y, top_center.z - r)
	var p1 := Vector3(top_center.x + r, top_center.y, top_center.z - r)
	var p2 := Vector3(top_center.x + r, top_center.y, top_center.z + r)
	var p3 := Vector3(top_center.x - r, top_center.y, top_center.z + r)
	var b0 := Vector3(p0.x, bottom_y - 2.0, p0.z)
	var b1 := Vector3(p1.x, bottom_y - 2.0, p1.z)
	var b2 := Vector3(p2.x, bottom_y - 2.0, p2.z)
	var b3 := Vector3(p3.x, bottom_y - 2.0, p3.z)
	add_quad(st, b0, b1, p1, p0, Vector3.FORWARD)
	add_quad(st, b1, b2, p2, p1, Vector3.RIGHT)
	add_quad(st, b2, b3, p3, p2, Vector3.BACK)
	add_quad(st, b3, b0, p0, p3, Vector3.LEFT)

## 3. 산악 관통 터널
static func build_mountain_tunnel(st: SurfaceTool, pts: Array[Vector3], width: float, tunnel_segments: Array[Dictionary]) -> void:
	var radius: float = width * 0.65
	var height_arch: float = width * 0.8

	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]

		tunnel_segments.append({
			"start": p0,
			"end": p1,
			"radius": radius + 6.0
		})

		var dir := (p1 - p0).normalized()
		var side := dir.cross(Vector3.UP).normalized() * radius
		var up_v := Vector3.UP * height_arch

		var a := p0 - side
		var b := p0 + side
		var c := p1 + side
		var d := p1 - side

		add_quad(st, a, b, c, d, Vector3.UP)

		var wa0 := a + up_v * 0.6
		var wb0 := b + up_v * 0.6
		var wc1 := c + up_v * 0.6
		var wd1 := d + up_v * 0.6
		add_quad(st, a, wa0, wd1, d, -side.normalized())
		add_quad(st, wb0, b, c, wc1, side.normalized())

		var top0 := p0 + up_v
		var top1 := p1 + up_v
		add_quad(st, wa0, top0, top1, wd1, (-side + Vector3.UP).normalized())
		add_quad(st, top0, wb0, wc1, top1, (side + Vector3.UP).normalized())

		if i == 0:
			build_tunnel_portal(st, p0, -dir, side, up_v)
		if i == pts.size() - 2:
			build_tunnel_portal(st, p1, dir, side, up_v)

## 터널 입출구 갱구(Portal) 콘크리트 아치 외벽
static func build_tunnel_portal(st: SurfaceTool, pos: Vector3, face_dir: Vector3, side: Vector3, up_v: Vector3) -> void:
	var pa := pos - side * 1.35
	var pb := pos + side * 1.35
	var ptop_a := pa + up_v * 1.3
	var ptop_b := pb + up_v * 1.3
	add_quad(st, pa, pb, ptop_b, ptop_a, face_dir)

static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)
