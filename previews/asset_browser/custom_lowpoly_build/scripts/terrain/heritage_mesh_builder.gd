extends RefCounted
class_name HeritageMeshBuilder

# 색상별로 합친 정적 메시. 돌 하나마다 노드를 만들지 않는다.
var surfaces: Dictionary = {}
var materials: Dictionary = {}
var used: Dictionary = {}
var random := RandomNumberGenerator.new()

func _init() -> void:
	random.seed = 39117
	for i in range(5):
		_material("stone%d" % i, Color(0.26 + i * 0.028, 0.25 + i * 0.028, 0.22 + i * 0.026))
	_material("cap", Color(0.37, 0.36, 0.32))
	_material("gate_stone", Color(0.4, 0.38, 0.34))
	_material("gate_wood", Color(0.34, 0.12, 0.075))
	_material("gate_green", Color(0.13, 0.29, 0.23))
	_material("gate_roof", Color(0.19, 0.21, 0.23))
	_material("gate_tile", Color(0.3, 0.32, 0.33))

func _material(key: String, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[key] = material
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surfaces[key] = surface

func box(key: String, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	used[key] = true
	var mesh := BoxMesh.new()
	mesh.size = size
	surfaces[key].append_from(mesh, 0, Transform3D(Basis(Vector3.UP, yaw), center))

func beam(key: String, a: Vector3, b: Vector3, width: float) -> void:
	used[key] = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, a.distance_to(b))
	var up := Vector3.RIGHT if absf((b - a).normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	surfaces[key].append_from(mesh, 0, Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5))

func triangle(key: String, a: Vector3, b: Vector3, c: Vector3) -> void:
	used[key] = true
	var normal := (b - a).cross(c - a).normalized()
	for vertex in [a, b, c]:
		surfaces[key].set_normal(normal)
		surfaces[key].add_vertex(vertex)

func wall(a: Vector2, b: Vector2, height: float, width: float, ruined: bool = false) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var direction := (b - a).normalized()
	var yaw := -atan2(direction.y, direction.x)
	var courses := maxi(1, ceili(height / 2.4))
	var row_height := height / courses
	for row in range(courses):
		var count := maxi(1, ceili(length / (8.0 - 1.6 * float(row) / courses)))
		var block_length := length / count
		for i in range(count):
			if ruined and row == courses - 1 and random.randf() < 0.22:
				continue
			var center := a.lerp(b, (float(i) + 0.5) / count)
			var taper := 1.0 - 0.43 * float(row) / courses
			var block_height := row_height - 0.035
			box("stone2", Vector3(center.x, row_height * (row + 0.5) - 0.6, center.y), Vector3(block_length - 0.045, block_height, width * taper), yaw)
	if not ruined:
		var count := maxi(1, ceili(length / 8.0))
		for i in range(count):
			var center := a.lerp(b, (float(i) + 0.5) / count)
			box("cap", Vector3(center.x, height - 0.53, center.y), Vector3(length / count - 0.03, 0.25, width * 0.58), yaw)

func roof(center: Vector3, width: float, depth: float, height: float) -> void:
	# 팔작지붕을 읽을 수 있도록 들린 추녀, 중간 곡면, 용마루를 분리한다.
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		outer.append(center + Vector3(p.x * width / 2, 0.45, p.y * depth / 2))
		inner.append(center + Vector3(p.x * width * 0.37, height * 0.36, p.y * depth * 0.34))
	var ridge_left := center + Vector3(-width * 0.26, height, 0)
	var ridge_right := center + Vector3(width * 0.26, height, 0)
	for i in range(4):
		var j := (i + 1) % 4
		triangle("gate_roof", outer[i], outer[j], inner[j])
		triangle("gate_roof", outer[i], inner[j], inner[i])
		beam("gate_green", outer[i] - Vector3.UP * 0.2, outer[j] - Vector3.UP * 0.2, 0.22)
	triangle("gate_roof", inner[0], inner[1], ridge_right)
	triangle("gate_roof", inner[0], ridge_right, ridge_left)
	triangle("gate_roof", inner[1], inner[2], ridge_right)
	triangle("gate_roof", inner[2], inner[3], ridge_left)
	triangle("gate_roof", inner[2], ridge_left, ridge_right)
	triangle("gate_roof", inner[3], inner[0], ridge_left)
	beam("gate_tile", ridge_left, ridge_right, 0.3)
	for side in [-1.0, 1.0]:
		for i in range(7):
			var x := lerpf(-width * 0.46, width * 0.46, float(i) / 6.0)
			var a := center + Vector3(clampf(x, -width * 0.26, width * 0.26), height + 0.035, 0)
			var b := center + Vector3(x * 0.8, height * 0.36 + 0.04, side * depth * 0.34)
			var c := center + Vector3(x, 0.49, side * depth * 0.5)
			beam("gate_tile", a, b, 0.085)
			beam("gate_tile", b, c, 0.085)

func finish(label: String) -> Node3D:
	var root := Node3D.new()
	root.name = label
	for key in surfaces:
		if not used.has(key):
			continue
		var mesh: ArrayMesh = surfaces[key].commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.name = key
		instance.mesh = mesh
		instance.material_override = materials[key]
		instance.visibility_range_end = 16000.0
		instance.visibility_range_end_margin = 500.0
		root.add_child(instance)
	return root
