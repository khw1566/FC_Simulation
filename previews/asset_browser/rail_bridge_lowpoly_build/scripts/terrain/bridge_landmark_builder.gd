extends RefCounted
class_name BridgeLandmarkBuilder

const Lighting = preload("res://scripts/core/asset_marker_lighting.gd")
const Geometry = preload("res://scripts/terrain/bridge_geometry.gd")

## 월드 좌표 경로를 사용하는 공통 교량/현수교/아치교/징검다리 생성기.
static func build(spec: Dictionary, route: Curve3D, terrain: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = str(spec.name)
	var geometry := Geometry.new()
	var length := route.get_baked_length()
	var width := float(spec.width_m)
	var kind := str(spec.kind)
	var start := route.sample_baked(0)
	var end := route.sample_baked(length)
	var bank_a := ground(terrain, start)
	var bank_b := ground(terrain, end)
	var deck := maxf(bank_a, bank_b) + float(spec.get("bank_clearance_m", 1.0))
	var span := minf(float(spec.get("main_span_m", length)), length)
	var tower_a := (length - span) * 0.5
	var tower_b := tower_a + span
	var count := maxi(2, int(ceil(length / 24.0)))
	if kind == "stepping_stones":
		count = maxi(2, int(length / 1.65))
		for i in range(count + 1):
			var p := route.sample_baked(length * i / count)
			p.y = float(spec.get("water_elevation_m", 0.0)) + 0.25
			geometry.beam(p - Vector3.UP * 0.65, p, 1.25, 1.0, "stone")
	else:
		for i in range(count):
			var d0 := length * i / count
			var d1 := length * (i + 1) / count
			var a := deck_point(route, d0, deck, bank_a, bank_b, kind, tower_a, tower_b)
			var b := deck_point(route, d1, deck, bank_a, bank_b, kind, tower_a, tower_b)
			# 도로 진행 방향에 수직인 단면을 구성한다.
			var lateral := Vector3((b - a).z, 0, -(b - a).x).normalized()
			deck_segment(geometry, a, b, lateral, width)
			for sign_value in [-1.0, 1.0]:
				var offset: Vector3 = lateral * width * 0.48 * sign_value
				geometry.beam(a + offset, a + offset + Vector3.UP * 1.25, 0.12, 0.12)
				geometry.beam(a + offset + Vector3.UP * 1.25, b + offset + Vector3.UP * 1.25, 0.10, 0.10)
				if kind == "historic":
					for step in range(1):
						var post: Vector3 = a.lerp(b, float(step) / 4.0) + offset
						geometry.beam(post, post + Vector3.UP * 1.1, 0.22, 0.22)
					geometry.beam(a + offset + Vector3.UP * 0.55, b + offset + Vector3.UP * 0.55, 0.15, 0.15)
		if kind == "suspension":
			suspension(geometry, route, tower_a, tower_b, width, terrain)
			var distance := 60.0
			while distance < length - 20.0:
				if distance < tower_a - 20.0 or distance > tower_b + 20.0:
					var top := deck_point(route, distance, deck, bank_a, bank_b, kind, tower_a, tower_b)
					var bottom := Vector3(top.x, ground(terrain, top) - 3.0, top.z)
					geometry.beam(bottom, top - Vector3.UP, 3.0, 3.0)
				distance += 60.0
		elif kind == "arch":
			arch(geometry, route, deck, span, width)
		else:
			var spacing := float(spec.get("pier_spacing_m", 32.0))
			var d := spacing
			while d < length - 4.0:
				var p := route.sample_baked(d)
				geometry.beam(Vector3(p.x, ground(terrain, p) - 3.0, p.z), Vector3(p.x, deck - 0.5, p.z), width * 0.65, 1.0)
				d += spacing
	geometry.finish(root)
	var light_points := PackedVector3Array()
	var lamp_count := mini(16, maxi(2, int(ceil(length / 120.0)) + 1))
	for i in range(lamp_count):
		var distance := length * i / (lamp_count - 1)
		var point := deck_point(route, distance, deck, bank_a, bank_b, kind, tower_a, tower_b)
		if kind == "stepping_stones":
			point.y = float(spec.get("water_elevation_m", 0.0)) + 0.25
		point.y += 0.8
		var tangent := route.sample_baked(minf(length, distance + 0.5)) - route.sample_baked(maxf(0.0, distance - 0.5))
		var side := Vector3(tangent.z, 0, -tangent.x).normalized()
		light_points.append(point + side * width * 0.44)
	Lighting.bridge(root, light_points)
	root.set_meta("source_osm_ids", spec.get("osm_ids", []))
	root.set_meta("dimensions_status", "공개 제원과 지도 선형 기반 근사 모델")
	return root

static func ground(terrain: Node3D, p: Vector3) -> float:
	if is_instance_valid(terrain) and terrain.has_method("get_terrain_elevation"):
		return float(terrain.call("get_terrain_elevation", p.x, p.z))
	return 0.0

static func deck_point(route: Curve3D, distance: float, deck: float, bank_a: float, bank_b: float, kind: String, a: float, b: float) -> Vector3:
	var p := route.sample_baked(distance)
	p.y = deck
	if kind == "suspension":
		p.y = 65.0
		if distance < a:
			p.y = lerpf(bank_a + 1.0, 65.0, smoothstep(0.0, a, distance))
		elif distance > b:
			p.y = lerpf(65.0, bank_b + 1.0, smoothstep(b, route.get_baked_length(), distance))
	return p

static func deck_segment(g, a: Vector3, b: Vector3, side: Vector3, width: float) -> void:
	# 부재 생성기의 임의 수직 기준 대신 도로 진행 방향으로 정확히 회전한다.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.8, a.distance_to(b) + 0.08)
	if not g.batches.has("deck"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		g.batches.deck = st
	var forward := (b - a).normalized()
	g.batches.deck.append_from(mesh, 0, Transform3D(Basis(side, forward.cross(side), forward), (a + b) * 0.5 - Vector3.UP * 0.4))

static func suspension(g, route: Curve3D, a: float, b: float, width: float, terrain: Node3D) -> void:
	for distance in [a, b]:
		var p := route.sample_baked(distance)
		var side := normal(route, distance)
		for sign_value in [-1.0, 1.0]:
			var foot: Vector3 = p + side * width * 0.57 * sign_value
			foot.y = ground(terrain, foot) - 8.0
			g.beam(foot, Vector3(foot.x, 203.0, foot.z), 6.0, 7.0)
		for level in [58.0, 170.0, 197.0]:
			g.beam(Vector3(p.x, level, p.z) - side * width * 0.57, Vector3(p.x, level, p.z) + side * width * 0.57, 4.0, 4.0)
	for sign_value in [-1.0, 1.0]:
		for i in range(12):
			var t0 := float(i) / 12.0
			var t1 := float(i + 1) / 12.0
			var d0 := lerpf(a, b, t0)
			var d1 := lerpf(a, b, t1)
			var p0: Vector3 = route.sample_baked(d0) + normal(route, d0) * width * 0.57 * sign_value
			var p1: Vector3 = route.sample_baked(d1) + normal(route, d1) * width * 0.57 * sign_value
			p0.y = 85.0 + 118.0 * pow(2.0 * t0 - 1.0, 2.0)
			p1.y = 85.0 + 118.0 * pow(2.0 * t1 - 1.0, 2.0)
			g.beam(p0, p1, 0.75, 0.75, "cable")
			g.beam(Vector3(p0.x, 65.0, p0.z), p0, 0.14, 0.14, "cable")
		for limits in [[0.0, a], [b, route.get_baked_length()]]:
			var first: Vector3 = route.sample_baked(limits[0]) + normal(route, limits[0]) * width * 0.57 * sign_value
			var last: Vector3 = route.sample_baked(limits[1]) + normal(route, limits[1]) * width * 0.57 * sign_value
			first.y = 203.0 if limits[0] == b else ground(terrain, first) + 6.0
			last.y = 203.0 if limits[1] == a else ground(terrain, last) + 6.0
			g.beam(first, last, 0.75, 0.75, "cable")

static func arch(g, route: Curve3D, deck: float, span: float, width: float) -> void:
	var begin := (route.get_baked_length() - span) * 0.5
	for sign_value in [-1.0, 1.0]:
		for i in range(8):
			var t0 := float(i) / 8.0
			var t1 := float(i + 1) / 8.0
			var d0 := begin + span * t0
			var d1 := begin + span * t1
			var p0: Vector3 = route.sample_baked(d0) + normal(route, d0) * width * 0.54 * sign_value
			var p1: Vector3 = route.sample_baked(d1) + normal(route, d1) * width * 0.54 * sign_value
			p0.y = deck + 30.0 * sin(PI * pow(t0, 0.75))
			p1.y = deck + 30.0 * sin(PI * pow(t1, 0.75))
			g.beam(p0, p1, 0.8, 0.8, "cable")
			if i % 2 == 0:
				g.beam(Vector3(p0.x, deck, p0.z), p0, 0.075, 0.075, "cable")

static func normal(route: Curve3D, distance: float) -> Vector3:
	var direction := route.sample_baked(minf(route.get_baked_length(), distance + 1.0)) - route.sample_baked(maxf(0.0, distance - 1.0))
	return Vector3(-direction.z, 0, direction.x).normalized()
