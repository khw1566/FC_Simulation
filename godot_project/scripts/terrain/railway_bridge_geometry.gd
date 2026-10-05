extends RefCounted
## 철도 교량의 병합 부재, 궤도, 가선 및 연결점을 만든다.

const Geometry = preload("res://scripts/terrain/bridge_geometry.gd")
const NightLighting = preload("res://scripts/terrain/railway_night_lighting.gd")
var geometry = Geometry.new()

func box(center: Vector3, size: Vector3, group: String = "structure") -> void:
	geometry.beam(center - Vector3.UP * size.y * 0.5, center + Vector3.UP * size.y * 0.5, size.x, size.z, group)

func beam(a: Vector3, b: Vector3, width: float, depth: float, group: String = "structure") -> void:
	geometry.beam(a, b, width, depth, group)

func track_centers(spec: Dictionary) -> Array[float]:
	var result: Array[float] = []
	var count := int(spec.get("track_count", 2))
	var spacing := float(spec.get("track_spacing_m", 5.0))
	for i in range(count):
		result.append((i - (count - 1) * 0.5) * spacing)
	return result

func tracks(spec: Dictionary) -> void:
	var length := float(spec.length_m)
	var gauge := float(spec.get("gauge_m", 1.435))
	var rail_top := float(spec.get("rail_top_y_m", 0.12))
	var wire_height := float(spec.get("catenary_height_m", 5.5))
	var centers := track_centers(spec)
	for x in centers:
		box(Vector3(x, -0.12, length * 0.5), Vector3(3.4, 0.24, length), "bed")
		for side in [-1.0, 1.0]:
			var rail_x: float = x + side * gauge * 0.5
			box(Vector3(rail_x, rail_top - 0.035, length * 0.5), Vector3(0.075, 0.07, length), "rails")
		var sleepers := maxi(1, int(ceil(length / 1.2)))
		for i in range(sleepers):
			box(Vector3(x, -0.02, (i + 0.5) * length / sleepers), Vector3(2.5, 0.09, 0.20), "sleepers")
		beam(Vector3(x, wire_height, 0), Vector3(x, wire_height, length), 0.025, 0.025, "wires")
		beam(Vector3(x, wire_height + 0.6, 0), Vector3(x, wire_height + 0.6, length), 0.018, 0.018, "wires")
		var wire_count := maxi(1, int(ceil(length / 8.0)))
		for i in range(wire_count):
			var z := (i + 0.5) * length / wire_count
			beam(Vector3(x, wire_height, z), Vector3(x, wire_height + 0.6, z), 0.015, 0.015, "wires")
	var pole_spacing := float(spec.get("catenary_spacing_m", 32.0))
	var pole_count := maxi(1, int(ceil(length / pole_spacing)))
	# 끝점 가선주는 다음 모듈이 담당하여 접속부 중복을 피한다.
	for i in range(pole_count):
		var z := i * length / pole_count
		for x in [-float(spec.width_m) * 0.46, float(spec.width_m) * 0.46]:
			beam(Vector3(x, 0, z), Vector3(x, wire_height + 1.2, z), 0.17, 0.17, "metal")
		beam(Vector3(-float(spec.width_m) * 0.46, wire_height + 1.0, z),
			Vector3(float(spec.width_m) * 0.46, wire_height + 1.0, z), 0.14, 0.16, "metal")
		for x in centers:
			beam(Vector3(x, wire_height + 0.65, z), Vector3(x, wire_height + 1.0, z), 0.10, 0.10, "insulator")

func parapets(length: float, width: float) -> void:
	for x in [-width * 0.5 + 0.10, width * 0.5 - 0.10]:
		box(Vector3(x, 0.30, length * 0.5), Vector3(0.20, 0.60, length))
		beam(Vector3(x, 1.1, 0), Vector3(x, 1.1, length), 0.065, 0.065, "metal")
		var count := maxi(1, int(ceil(length / 2.5)))
		for i in range(count):
			var z := i * length / count
			beam(Vector3(x, 0.6, z), Vector3(x, 1.1, z), 0.06, 0.06, "metal")

func pier(z: float, width: float, height: float) -> void:
	box(Vector3(0, -height * 0.5 - 1.3, z), Vector3(2.4, height - 2.6, 2.8))
	box(Vector3(0, -2.25, z), Vector3(width * 0.85, 0.9, 3.2))
	box(Vector3(0, -height + 0.4, z), Vector3(5.4, 0.8, 5.0))
	for x in [-width * 0.28, width * 0.28]:
		box(Vector3(x, -1.70, z), Vector3(0.8, 0.25, 1.2), "metal")

func finish(root: Node3D, spec: Dictionary) -> void:
	geometry.finish(root)
	var colors := {"structure": Color(0.65, 0.65, 0.63), "deck": Color(0.48, 0.49, 0.48),
		"bed": Color(0.57, 0.58, 0.59), "rails": Color(0.43, 0.47, 0.51),
		"sleepers": Color(0.70, 0.69, 0.66), "metal": Color(0.47, 0.53, 0.58),
		"steel": Color(0.28, 0.40, 0.42), "arch": Color(0.75, 0.79, 0.80),
		"wires": Color(0.18, 0.20, 0.21), "insulator": Color(0.38, 0.28, 0.18),
		"platform": Color(0.72, 0.72, 0.68), "edge": Color(0.78, 0.68, 0.24)}
	for child in root.get_children():
		if child is MeshInstance3D:
			var material := StandardMaterial3D.new()
			material.albedo_color = colors.get(str(child.name), Color.GRAY)
			material.roughness = 0.8
			if child.name in ["metal", "rails", "steel", "arch"]:
				material.metallic = 0.5
			child.material_override = material
	var rail_top := float(spec.get("rail_top_y_m", 0.12))
	marker(root, "TrackStart", Vector3(0, rail_top, 0))
	marker(root, "TrackEnd", Vector3(0, rail_top, float(spec.length_m)))
	var centers := track_centers(spec)
	for i in range(centers.size()):
		marker(root, "Track%dStart" % i, Vector3(centers[i], rail_top, 0))
		marker(root, "Track%dEnd" % i, Vector3(centers[i], rail_top, float(spec.length_m)))
	root.set_meta("length_m", spec.length_m)
	root.set_meta("track_count", int(spec.get("track_count", 2)))
	root.set_meta("gauge_m", float(spec.get("gauge_m", 1.435)))
	root.set_meta("track_spacing_m", float(spec.get("track_spacing_m", 5.0)))
	root.set_meta("rail_top_y_m", rail_top)
	root.set_meta("connection_axis", "+Z")
	NightLighting.structure(root, float(spec.length_m), float(spec.width_m) * 0.5 - 0.12, 1.1)

static func marker(root: Node3D, label: String, point: Vector3) -> void:
	var node := Marker3D.new()
	node.name = label
	node.position = point
	root.add_child(node)
