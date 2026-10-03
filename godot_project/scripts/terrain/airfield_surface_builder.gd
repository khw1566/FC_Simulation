extends RefCounted
class_name AirfieldSurfaceBuilder

const Layout = preload("res://scripts/terrain/airfield_layout.gd")
const DIGITS := {
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"8": ["01110", "11011", "11011", "01110", "11011", "11011", "01110"],
	"3": ["11110", "00011", "00011", "01110", "00011", "00011", "11110"],
	"6": ["01110", "11000", "11000", "11110", "11011", "11011", "01110"]
}
var _spec: Dictionary
var _surfaces: Dictionary = {}

func build(spec: Dictionary) -> Node3D:
	_spec = spec
	_surfaces.clear()
	var root := Node3D.new()
	root.name = "AirfieldSurfaces"
	for key in ["asphalt", "white", "yellow", "shoulder"]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[key] = surface
	var length: float = spec.airfield.length_m
	var half: float = spec.airfield.width_m / 2
	_rect("asphalt", -half, -length, half * 2, length)
	_rect("shoulder", -half - 3, -length, 3, length)
	_rect("shoulder", half, -length, 3, length)
	_rect("asphalt", Layout.APRON.position.x, Layout.APRON.position.y, Layout.APRON.size.x, Layout.APRON.size.y)
	for path in [Layout.TAXI_A, Layout.TAXI_B, Layout.TAXILANE]:
		for i in range(path.size() - 1):
			_strip("asphalt", path[i], path[i + 1], float(spec.airfield.taxiway_width_m))
			_strip("yellow", path[i], path[i + 1], 0.4)
	for side in [-1.0, 1.0]:
		_rect("white", side * (half - 1) - 0.25, -length, 0.5, length)
	for z in range(120, int(length) - 110, 60):
		_rect("white", -0.45, -z - 30, 0.9, 30)
	for end in [0, 1]:
		var sign: float = 1 if end == 0 else -1
		var start: float = 0 if end == 0 else -length
		for i in range(6):
			for side in [-1.0, 1.0]:
				_mark_rect(side * (4 + i * 2.7), start - sign * 23, 1.8, 30)
		for side in [-1.0, 1.0]:
			_mark_rect(side * 13, start - sign * 300, 6, 45)
			for station in [150.0, 450.0, 600.0]:
				_mark_rect(side * 12, start - sign * station, 2, 22)
		_number(root, "36" if end == 0 else "18", start - sign * 80, end == 1)
	# 활주로 진입 전 정지 위치와 계류장 유도선.
	for z in [-1040.0, -910.0]:
		for x in [60.0, 61.0]:
			_rect("yellow", x, z - 14, 0.3, 28)
		for x in [63.0, 64.0]:
			for row in range(7):
				_rect("yellow", x, z - 14 + row * 4, 0.3, 2)
	for z in [-845.0, -902.0, -978.0, -1038.0]:
		_strip("yellow", Vector2(190, z), Vector2(312, z), 0.35)
		_strip("yellow", Vector2(300, z - 4), Vector2(300, z + 4), 0.35)
	var colors := {"asphalt": Color(0.09, 0.1, 0.11), "white": Color(0.9, 0.9, 0.86), "yellow": Color(0.9, 0.64, 0.06), "shoulder": Color(0.22, 0.23, 0.22)}
	for key in _surfaces:
		var mesh: ArrayMesh = _surfaces[key].commit()
		var instance := MeshInstance3D.new()
		instance.name = "Pavement_" + key
		instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[key]
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		instance.material_override = material
		instance.visibility_range_end = 22000
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
		if key == "asphalt":
			instance.create_trimesh_collision()
	return root

func _point(key: String, point: Vector2) -> Vector3:
	var lift: float = 0.12 if key in ["white", "yellow"] else 0
	return Vector3(point.x, Layout.height_at(point.x, point.y, _spec) + lift, point.y)

func _quad(key: String, corners: Array) -> void:
	var surface: SurfaceTool = _surfaces[key]
	for i in [0, 2, 1, 0, 3, 2]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(_point(key, corners[i]))

func _rect(key: String, x: float, z: float, width: float, depth: float) -> void:
	# 경사 보간이 바뀌는 유도로를 짧은 구간으로 나누어 지면과 맞춘다.
	var nx := maxi(1, int(ceil(width / 10)))
	var nz := maxi(1, int(ceil(depth / 20)))
	for ix in range(nx):
		for iz in range(nz):
			var a := Vector2(x + width * ix / nx, z + depth * iz / nz)
			var b := a + Vector2(width / nx, depth / nz)
			_quad(key, [a, Vector2(a.x, b.y), b, Vector2(b.x, a.y)])

func _strip(key: String, a: Vector2, b: Vector2, width: float) -> void:
	var normal := (b - a).normalized().orthogonal() * width / 2
	var count := maxi(1, int(ceil(a.distance_to(b) / 10)))
	for i in range(count):
		var start := a.lerp(b, float(i) / count)
		var end := a.lerp(b, float(i + 1) / count)
		_quad(key, [start - normal, end - normal, end + normal, start + normal])

func _mark_rect(x: float, z: float, width: float, depth: float) -> void:
	_rect("white", x - width / 2, z - depth / 2, width, depth)

func _number(_root: Node3D, value: String, z: float, reverse: bool) -> void:
	var direction: float = -1 if reverse else 1
	for digit in range(2):
		for row in range(7):
			for col in range(5):
				if DIGITS[value[digit]][row][col] == "1":
					_mark_rect(direction * (-6 + digit * 7 + col), z + direction * (row - 3) * 2.5, 1.05, 2.6)
