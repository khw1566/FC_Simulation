extends RefCounted
class_name AirfieldTerrainGrader

const Layout = preload("res://scripts/terrain/airfield_layout.gd")
const Sampler = preload("res://scripts/terrain/coastline_water_carver.gd")

static func apply(image: Image, spec: Dictionary, meta: Dictionary, min_y: float, max_y: float) -> float:
	var size: float = meta.world_size_meters
	var frame := Layout.world_frame(spec, meta)
	var inverse := frame.affine_inverse()
	var anchor := Layout.geo(float(spec.anchor.lat), float(spec.anchor.lon), meta)
	var rotation := Basis(Vector3.UP, deg_to_rad(float(spec.rotation_y_degrees)))
	var floor_y: float = -INF
	for building in spec.buildings:
		for sx in [-0.5, 0.0, 0.5]:
			for sz in [-0.5, 0.0, 0.5]:
				var p := anchor + rotation * Vector3(float(building.center_xz[0]) + float(building.size_xz[0]) * sx, 0, float(building.center_xz[1]) + float(building.size_xz[1]) * sz)
				floor_y = maxf(floor_y, Sampler.sample_elevation_bilinear(image, p.x, p.z, size, min_y, max_y))
	floor_y += 0.15
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x in [-155.0, 470.0]:
		for z in [-2450.0, 850.0]:
			var p := frame * Vector3(x, 0, z)
			var pixel := Vector2((p.x / size + 0.5) * (image.get_width() - 1), (p.z / size + 0.5) * (image.get_height() - 1))
			low = low.min(pixel)
			high = high.max(pixel)
	for py in range(maxi(0, int(low.y)), mini(image.get_height(), int(ceil(high.y)) + 1)):
		for px in range(maxi(0, int(low.x)), mini(image.get_width(), int(ceil(high.x)) + 1)):
			var world := Vector3((float(px) / (image.get_width() - 1) - 0.5) * size, 0, (float(py) / (image.get_height() - 1) - 0.5) * size)
			var p := inverse * world
			var distance := Layout.pavement_distance(Vector2(p.x, p.z), spec)
			if distance > 120:
				continue
			var weight: float = 1.0 - smoothstep(60, 120, distance)
			var target: float = (floor_y + Layout.height_at(p.x, p.z, spec) - 0.6 - min_y) / (max_y - min_y)
			image.set_pixel(px, py, Color(lerpf(image.get_pixel(px, py).r, target, weight), 0, 0))
	return floor_y
