extends RefCounted
## 교량 부재 생성과 재질 설정을 공통화한다.

const Geometry = preload("res://scripts/terrain/bridge_geometry.gd")
var geometry = Geometry.new()

func box(center: Vector3, size: Vector3, group: String = "structure") -> void:
	geometry.beam(center - Vector3.UP * size.y * 0.5, center + Vector3.UP * size.y * 0.5, size.x, size.z, group)

func beam(a: Vector3, b: Vector3, width: float, depth: float, group: String = "structure") -> void:
	geometry.beam(a, b, width, depth, group)

func rail(a: Vector3, b: Vector3, height: float = 1.2, glass: bool = false) -> void:
	var count := maxi(1, int(ceil(a.distance_to(b) / 2.0)))
	for i in range(count + 1):
		var p := a.lerp(b, float(i) / count)
		beam(p, p + Vector3.UP * height, 0.065, 0.065, "metal")
	beam(a + Vector3.UP * height, b + Vector3.UP * height, 0.07, 0.07, "metal")
	if glass:
		beam(a + Vector3.UP * height * 0.5, b + Vector3.UP * height * 0.5, height * 0.75, 0.035, "glass")
	else:
		beam(a + Vector3.UP * height * 0.5, b + Vector3.UP * height * 0.5, 0.055, 0.055, "metal")
		for i in range(count * 5):
			var p := a.lerp(b, (float(i) + 0.5) / (count * 5))
			beam(p + Vector3.UP * 0.15, p + Vector3.UP * (height - 0.10), 0.025, 0.025, "metal")

func finish(root: Node3D) -> void:
	geometry.finish(root)
	var colors := {"structure": Color(0.64, 0.65, 0.64), "deck": Color(0.21, 0.22, 0.23),
		"stone": Color(0.59, 0.58, 0.54), "metal": Color(0.64, 0.68, 0.70),
		"paving": Color(0.73, 0.72, 0.67), "markings": Color(0.92, 0.91, 0.85),
		"yellow": Color(0.78, 0.65, 0.22), "glass": Color(0.56, 0.72, 0.75, 0.32)}
	for child in root.get_children():
		if not child is MeshInstance3D:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = colors.get(str(child.name), Color.GRAY)
		material.roughness = 0.8
		if child.name == "glass":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.roughness = 0.2
		elif child.name == "metal":
			material.metallic = 0.45
		child.material_override = material

static func marker(root: Node3D, label: String, point: Vector3) -> void:
	var node := Marker3D.new()
	node.name = label
	node.position = point
	root.add_child(node)
