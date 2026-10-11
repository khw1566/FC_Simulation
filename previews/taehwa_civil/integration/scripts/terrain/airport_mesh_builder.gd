extends RefCounted
class_name AirportMeshBuilder

# 재질별로 정적 메시를 합쳐 창틀 수에 따라 드로우 콜이 증가하지 않게 한다.
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var _root: Node3D

func build(spec: Dictionary) -> Node3D:
	_root = Node3D.new()
	_root.name = "UlsanAirportModel"
	_surfaces.clear()
	_materials.clear()
	_material("wall", Color(0.76, 0.78, 0.79), 0.8)
	_material("frame", Color(0.88, 0.9, 0.91), 0.5)
	_material("glass", Color(0.12, 0.23, 0.28), 0.23, 0.45)
	_material("roof", Color(0.5, 0.55, 0.58), 0.65)
	_material("dark", Color(0.16, 0.19, 0.2), 0.8)
	_material("concrete", Color(0.47, 0.48, 0.47), 0.95)
	_build_terminal(spec.terminal)
	_build_tower(spec.tower)
	for building in spec.buildings:
		if building.id != "terminal":
			_build_annex(building)
	_finish_meshes()
	return _root

func _material(key: String, color: Color, roughness: float, metal: float = 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	_materials[key] = material
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_surfaces[key] = surface

func _box(key: String, center: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var transform := Transform3D(Basis.from_euler(rotation), center)
	_surfaces[key].append_from(mesh, 0, transform)

func _cylinder(key: String, center: Vector3, bottom: float, top: float, height: float, sides: int = 8) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = sides
	_surfaces[key].append_from(mesh, 0, Transform3D(Basis.IDENTITY, center))

func _collision(label: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_root.add_child(body)

func _build_terminal(spec: Dictionary) -> void:
	var width: float = spec.width
	var depth: float = spec.depth
	var height: float = spec.height
	_box("wall", Vector3(0, height / 2, 0), Vector3(width, height, depth))
	# 지형과 건물 사이 틈을 가리는 매립 기초.
	_box("concrete", Vector3(0, -4, 0), Vector3(width + 1, 8, depth + 1))
	_collision("TerminalCollision", Vector3(0, (height - 8) / 2, 0), Vector3(width, height + 8, depth))
	for side in [-1.0, 1.0]:
		var front_z: float = side * (depth / 2 + 0.08)
		_box("glass", Vector3(0, 6.5, front_z), Vector3(width - 1, 9.2, 0.14))
		for y in [2.0, 5.0, 8.0, 11.0]:
			_box("frame", Vector3(0, y, front_z + side * 0.14), Vector3(width, 0.18, 0.22))
		for i in range(33):
			var x: float = -width / 2 + width * i / 32.0
			_box("frame", Vector3(x, 6.5, front_z + side * 0.14), Vector3(0.16, 9.4, 0.24))
	# 완만하게 꺾인 금속 지붕과 처마.
	for side in [-1.0, 1.0]:
		_box("roof", Vector3(0, height + 0.9, side * depth / 4), Vector3(width + 3, 0.6, depth / 2 + 1.5), Vector3(side * 0.065, 0, 0))
	_box("frame", Vector3(0, height + 0.15, depth / 2 + 0.8), Vector3(width + 3, 1.0, 0.6))
	# 도로 측 캐노피, 기둥, 출입문.
	_box("frame", Vector3(0, 4.1, depth / 2 + 4), Vector3(width - 4, 0.35, 8))
	for x in [-34.0, -22.0, -10.0, 2.0, 14.0, 26.0, 34.0]:
		_cylinder("frame", Vector3(x, 2, depth / 2 + 7), 0.19, 0.19, 4, 8)
	for x in [-24.0, 0.0, 24.0]:
		_box("dark", Vector3(x, 1.8, depth / 2 + 0.3), Vector3(5, 3.5, 0.2))
		_box("glass", Vector3(x, 1.9, depth / 2 + 0.45), Vector3(4.5, 3.1, 0.1))
	_box("concrete", Vector3(0, -0.15, depth / 2 + 5), Vector3(width + 5, 0.3, 10))
	_collision("CanopyCollision", Vector3(0, 4.1, depth / 2 + 4), Vector3(width - 4, 0.35, 8))
	var label := Label3D.new()
	label.name = "AirportSign"
	label.text = "울산공항  ULSAN AIRPORT"
	label.font_size = 96
	label.pixel_size = 0.025
	label.modulate = Color(0.85, 0.12, 0.1)
	label.outline_size = 0
	label.position = Vector3(0, height + 2.1, depth / 2 + 0.85)
	label.no_depth_test = false
	label.visibility_range_end = 8000.0
	label.visibility_range_end_margin = 300.0
	_root.add_child(label)

func _build_tower(spec: Dictionary) -> void:
	var x: float = spec.center_xz[0]
	var z: float = spec.center_xz[1]
	var h: float = spec.height
	_box("wall", Vector3(x, (h - 7) / 2, z), Vector3(8, h - 7, 8))
	for y in [13.0, 17.0, 21.0]:
		_box("glass", Vector3(x, y, z + 4.05), Vector3(3.5, 1.5, 0.16))
	_cylinder("frame", Vector3(x, h - 7.5, z), 5.8, 5.8, 0.6)
	_cylinder("glass", Vector3(x, h - 5.5, z), 4.4, 5.3, 3.4)
	_cylinder("frame", Vector3(x, h - 3.6, z), 5.8, 5.8, 0.45)
	_cylinder("roof", Vector3(x, h - 3.0, z), 5.8, 2.0, 0.9)
	_cylinder("dark", Vector3(x, h - 1.3, z), 0.12, 0.12, 2.6)
	for i in range(8):
		var angle: float = TAU * i / 8.0
		_box("frame", Vector3(x + sin(angle) * 4.9, h - 5.5, z + cos(angle) * 4.9), Vector3(0.16, 3.6, 0.16))
	_collision("TowerCollision", Vector3(x, (h - 3) / 2, z), Vector3(9, h - 3, 9))

func _build_annex(spec: Dictionary) -> void:
	var x: float = spec.center_xz[0]
	var z: float = spec.center_xz[1]
	var w: float = spec.size_xz[0]
	var d: float = spec.size_xz[1]
	var h: float = spec.height
	_box("wall", Vector3(x, h / 2, z), Vector3(w, h, d))
	_box("concrete", Vector3(x, -4, z), Vector3(w, 8, d))
	_box("roof", Vector3(x, h + 0.25, z), Vector3(w + 1.2, 0.5, d + 1.2))
	_collision(str(spec.id) + "Collision", Vector3(x, (h - 8) / 2, z), Vector3(w, h + 8, d))
	if spec.id == "fire_station":
		for i in range(4):
			_box("dark", Vector3(x - 10.5 + i * 7, 2.5, z - d / 2 - 0.1), Vector3(5.5, 5, 0.2))
			for y in [1.0, 2.0, 3.0, 4.0]:
				_box("roof", Vector3(x - 10.5 + i * 7, y, z - d / 2 - 0.22), Vector3(5.5, 0.08, 0.1))
	else:
		for side in [-1.0, 1.0]:
			_box("glass", Vector3(x, h * 0.65, z + side * (d / 2 + 0.1)), Vector3(w - 3, 2, 0.15))

func _finish_meshes() -> void:
	for key in _surfaces:
		var mesh: ArrayMesh = _surfaces[key].commit()
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Geometry_" + key
		instance.mesh = mesh
		instance.material_override = _materials[key]
		instance.visibility_range_end = 14000.0
		instance.visibility_range_end_margin = 500.0
		_root.add_child(instance)
