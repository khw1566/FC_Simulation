extends RefCounted
class_name AirfieldLightBuilder

const Layout = preload("res://scripts/terrain/airfield_layout.gd")
const LightShader = preload("res://shaders/airfield_light.gdshader")
var _groups: Dictionary = {}
var _spec: Dictionary

func build(spec: Dictionary) -> Node3D:
	_spec = spec
	_groups.clear()
	var length: float = spec.airfield.length_m
	var half: float = spec.airfield.width_m / 2
	for distance in range(0, int(length) + 1, int(spec.airfield.edge_light_spacing_m)):
		for side in [-1.0, 1.0]:
			_add("white", Vector2(side * (half + 0.8), -distance))
	for side in [-1.0, 1.0]:
		_add("white", Vector2(side * (half + 0.8), -length))
	for end in [0, 1]:
		var z: float = 0 if end == 0 else -length
		var angle: float = 0 if end == 0 else PI
		for i in range(12):
			var point := Vector2(lerpf(-half, half, i / 11.0), z)
			_add("green_directional", point, angle)
			_add("red_directional", point, angle + PI)
		var reach: float = spec.airfield.approach_36_m if end == 0 else spec.airfield.approach_18_m
		var direction: float = 1 if end == 0 else -1
		for station in range(30, int(reach) + 1, 30):
			for x in [-1.5, 0.0, 1.5]:
				_add("white_directional", Vector2(x, z + direction * station), angle)
		for x in range(-15, 16, 3):
			_add("white_directional", Vector2(x, z + direction * 300), angle)
	for path in [Layout.TAXI_A, Layout.TAXI_B, Layout.TAXILANE]:
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var normal := (b - a).normalized().orthogonal() * (float(spec.airfield.taxiway_width_m) / 2 + 0.5)
			var count := maxi(1, int(ceil(a.distance_to(b) / float(spec.airfield.taxi_light_spacing_m))))
			for j in range(count):
				var point := a.lerp(b, float(j) / count)
				# 다른 포장면과 만나는 곳에는 가장자리 등을 두지 않는다.
				if point.x < 35 or (i == 0 and j == 0 and path == Layout.TAXILANE):
					continue
				for side in [-1.0, 1.0]:
					_add("blue", point + normal * side)
	var root := Node3D.new()
	root.name = "AirfieldLights"
	var colors := {"white": Color(1, 0.92, 0.78), "green": Color(0.1, 1, 0.22), "red": Color(1, 0.05, 0.015), "blue": Color(0.05, 0.3, 1)}
	var total: int = 0
	for key in _groups:
		var points: Array = _groups[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = QuadMesh.new()
		multimesh.instance_count = points.size()
		for i in range(points.size()):
			multimesh.set_instance_transform(i, points[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Lamps_" + key
		instance.multimesh = multimesh
		var material := ShaderMaterial.new()
		material.shader = LightShader
		material.set_shader_parameter("light_color", colors[key.split("_")[0]])
		material.set_shader_parameter("directional", key.ends_with("directional"))
		instance.material_override = material
		instance.extra_cull_margin = 5
		instance.visibility_range_end = 18000
		root.add_child(instance)
		total += points.size()
	root.set_meta("lamp_count", total)
	return root

func _add(key: String, point: Vector2, angle: float = 0.0) -> void:
	if not _groups.has(key):
		_groups[key] = []
	var position := Vector3(point.x, Layout.height_at(point.x, point.y, _spec) + 0.6, point.y)
	_groups[key].append(Transform3D(Basis(Vector3.UP, angle), position))
