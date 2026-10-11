extends RefCounted
## 재질별 메시 배치로 활주로·표식·건물·등화를 생성한다.
const RunwayLabel = preload("res://scripts/terrain/lowpoly_runway_label.gd")
const Layout = preload("res://scripts/terrain/regional_airport_layout.gd")
var _surfaces: Dictionary = {}
var _root: Node3D

func build(spec: Dictionary) -> Node3D:
	_root = Node3D.new()
	_root.name = spec.id
	_surfaces.clear()
	for key in ["ground", "pavement", "marking", "wall", "glass", "roof", "lights"]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[key] = tool
	var bounds := Layout.bounds(spec)
	_box("ground", Vector3(bounds.get_center().x, -1.0, bounds.get_center().y), Vector3(bounds.size.x, 2, bounds.size.y))
	for runway in spec.runways:
		var a := Vector3(runway.start[0], 0.08, runway.start[1])
		var b := Vector3(runway.end[0], 0.08, runway.end[1])
		_strip("pavement", a, b, runway.width_m, 0.15)
		var length := a.distance_to(b)
		var direction := (b - a).normalized()
		var side := direction.cross(Vector3.UP)
		var designations: PackedStringArray = str(runway.designation).split("/")
		for end_index in range(2):
			var text := TextMesh.new()
			text.text = designations[end_index]
			text.font_size = 64
			text.pixel_size = 0.18
			text.depth = 0.02
			var sign_value: float = 1 if end_index == 0 else -1
			var origin: Vector3 = (a if end_index == 0 else b) + direction * sign_value * 65 + Vector3.UP * 0.13
			RunwayLabel.append(_surfaces.marking, designations[end_index], Transform3D(Basis(side * sign_value, -direction * sign_value, Vector3.UP), origin))
		for t in range(0, int(length), 120):
			_strip("marking", a + direction * t + Vector3.UP * 0.12, a + direction * minf(t + 30, length) + Vector3.UP * 0.12, 0.9, 0.03)
		for end in [a + direction * 12, b - direction * 12]:
			for lane in range(-4, 5):
				var center: Vector3 = end + side * lane * 3.5 + Vector3.UP * 0.13
				_strip("marking", center - direction * 10, center + direction * 10, 1.5, 0.03)
		for t in range(0, int(length), 120):
			for sign_value in [-1, 1]:
				_box("lights", a + direction * t + side * sign_value * (float(runway.width_m) / 2 + 1) + Vector3.UP * 0.4, Vector3(0.5, 0.35, 0.5))
	for feature in spec.features:
		if feature.kind == "taxiway":
			for i in range(feature.points.size() - 1):
				var a := _point(feature.points[i], 0.12)
				var b := _point(feature.points[i + 1], 0.12)
				if a.distance_squared_to(b) > 0.01:
					_strip("pavement", a, b, feature.get("width_m", 23), 0.14)
		elif feature.kind == "apron":
			_polygon("pavement", feature.points, 0.14)
		else:
			_building(feature)
	if not spec.features.any(func(f): return f.kind == "terminal"):
		var runway: Dictionary = spec.runways[0]
		var a := Vector2(runway.start[0], runway.start[1])
		var b := Vector2(runway.end[0], runway.end[1])
		var direction := (b - a).normalized()
		var side := Vector2(-direction.y, direction.x)
		var center := (a + b) / 2 + side * 220
		var width: float = 160 if spec.kind == "civil" else 110
		var points := []
		for p in [Vector2(-width / 2, -25), Vector2(width / 2, -25), Vector2(width / 2, 25), Vector2(-width / 2, 25)]:
			var v: Vector2 = center + direction * p.x + side * p.y
			points.append([v.x, v.y])
		_building({"kind": "terminal", "points": points, "height_m": 15})
		_strip("pavement", _point([center.x, center.y], 0.12), _point([(a.x + b.x) / 2, (a.y + b.y) / 2], 0.12), 23, 0.14)
		_box("pavement", Vector3(center.x, 0.1, center.y) - Vector3(side.x, 0, side.y) * 60, Vector3(180, 0.2, 120))
	var colors := {"ground": Color(0.34, 0.37, 0.30), "pavement": Color(0.17, 0.18, 0.19), "marking": Color(0.94, 0.94, 0.90), "wall": Color(0.75, 0.77, 0.78), "glass": Color(0.16, 0.24, 0.28), "roof": Color(0.43, 0.46, 0.48), "lights": Color(1, 0.93, 0.72)}
	var first: Dictionary = spec.runways[0]
	var mid := Vector3((float(first.start[0]) + float(first.end[0])) / 2, 0, (float(first.start[1]) + float(first.end[1])) / 2)
	var axis := (_point(first.end, 0) - _point(first.start, 0)).normalized()
	var tower := mid + axis.cross(Vector3.UP) * 180 + axis * 160
	_box("wall", tower + Vector3.UP * 15, Vector3(10, 30, 10))
	_box("glass", tower + Vector3.UP * 32, Vector3(16, 6, 16))
	_box("roof", tower + Vector3.UP * 35.5, Vector3(18, 1, 18))
	for key in _surfaces:
		var mesh: ArrayMesh = _surfaces[key].commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[key]
		material.roughness = 0.85
		if key == "lights":
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.emission_enabled = true
			material.emission = colors[key]
			material.emission_energy_multiplier = 2
		var node := MeshInstance3D.new()
		node.name = key
		node.mesh = mesh
		node.material_override = material
		node.visibility_range_end = 16000
		if key in ["marking", "lights"]:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(node)
		if key in ["ground", "wall"]:
			node.create_trimesh_collision()
	return _root

func _point(p: Array, y: float) -> Vector3:
	return Vector3(float(p[0]), y, float(p[1]))

func _box(key: String, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_surfaces[key].append_from(mesh, 0, Transform3D(basis, center))

func _strip(key: String, a: Vector3, b: Vector3, width: float, depth: float) -> void:
	if a.distance_squared_to(b) < 0.001:
		return
	_box(key, (a + b) / 2, Vector3(width, depth, a.distance_to(b)), Basis.looking_at((b - a).normalized()))

func _polygon(key: String, points: Array, y: float) -> void:
	var polygon := PackedVector2Array()
	for p in points:
		polygon.append(Vector2(p[0], p[1]))
	if polygon.size() > 1 and polygon[0].is_equal_approx(polygon[-1]):
		polygon.remove_at(polygon.size() - 1)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		for index in [indices[i], indices[i + 2], indices[i + 1]]:
			var p := polygon[index]
			_surfaces[key].set_normal(Vector3.UP)
			_surfaces[key].add_vertex(Vector3(p.x, y, p.y))

func _building(feature: Dictionary) -> void:
	var points: Array = feature.points
	var height: float = feature.get("height_m", 15)
	_polygon("roof", points, height)
	var count := points.size() - 1 if points[0] == points[-1] else points.size()
	for i in range(count):
		var a := _point(points[i], height / 2)
		var b := _point(points[(i + 1) % count], height / 2)
		if a.distance_squared_to(b) < 0.01:
			continue
		_strip("wall", a, b, 0.7, height)
		_strip("glass", a + Vector3.UP * 1.0, b + Vector3.UP * 1.0, 0.9, minf(height * 0.45, 6))
		var intervals := maxi(2, int(a.distance_to(b) / 24))
		for j in range(intervals + 1):
			_box("roof", a.lerp(b, float(j) / intervals), Vector3(0.25, height, 0.25))
