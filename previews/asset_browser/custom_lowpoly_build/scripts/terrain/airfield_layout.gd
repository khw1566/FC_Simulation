extends RefCounted
class_name AirfieldLayout

const APRON := Rect2(180, -1120, 160, 300)
const TAXI_A := [Vector2(0, -1040), Vector2(75, -1040), Vector2(100, -1050), Vector2(135, -1090), Vector2(180, -1100)]
const TAXI_B := [Vector2(0, -910), Vector2(75, -910), Vector2(105, -890), Vector2(140, -850), Vector2(180, -850)]
const TAXILANE := [Vector2(165, -1100), Vector2(165, -850)]

static func geo(lat: float, lon: float, meta: Dictionary) -> Vector3:
	return Vector3(((lon - float(meta.bbox.west)) / (float(meta.bbox.east) - float(meta.bbox.west)) - 0.5) * float(meta.world_size_meters), 0, ((float(meta.bbox.north) - lat) / (float(meta.bbox.north) - float(meta.bbox.south)) - 0.5) * float(meta.world_size_meters))

static func world_frame(spec: Dictionary, meta: Dictionary) -> Transform3D:
	var a: Dictionary = spec.airfield.threshold_36
	var b: Dictionary = spec.airfield.threshold_18
	var south := geo(float(a.lat), float(a.lon), meta)
	var north := geo(float(b.lat), float(b.lon), meta)
	var direction := (north - south).normalized()
	return Transform3D(Basis.looking_at(direction), (south + north) / 2 - direction * float(spec.airfield.length_m) / 2)

static func local_frame(spec: Dictionary, meta: Dictionary) -> Transform3D:
	var anchor := geo(float(spec.anchor.lat), float(spec.anchor.lon), meta)
	var terminal := Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec.rotation_y_degrees))), anchor)
	return terminal.affine_inverse() * world_frame(spec, meta)

static func height_at(x: float, z: float, spec: Dictionary) -> float:
	var south: float = spec.airfield.threshold_36.elevation_m
	var north: float = spec.airfield.threshold_18.elevation_m
	var runway_y := lerpf(south, north, clampf(-z / float(spec.airfield.length_m), 0, 1)) - float(spec.reference_elevation_m)
	return lerpf(runway_y, 0.0, clampf((x - 25) / 155.0, 0, 1))

static func pavement_distance(point: Vector2, spec: Dictionary) -> float:
	var runway := Rect2(-float(spec.airfield.width_m) / 2, -float(spec.airfield.length_m), float(spec.airfield.width_m), float(spec.airfield.length_m))
	var distance := minf(_rect_distance(point, runway), _rect_distance(point, APRON))
	for path in [TAXI_A, TAXI_B, TAXILANE]:
		for i in range(path.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])
			distance = minf(distance, point.distance_to(closest) - float(spec.airfield.taxiway_width_m) / 2)
	# 진입등 지지면을 위한 좁은 띠.
	for strip in [Rect2(-6, 0, 12, float(spec.airfield.approach_36_m)), Rect2(-6, -float(spec.airfield.length_m) - float(spec.airfield.approach_18_m), 12, float(spec.airfield.approach_18_m))]:
		distance = minf(distance, _rect_distance(point, strip))
	return distance

static func _rect_distance(point: Vector2, rect: Rect2) -> float:
	var d := (point - rect.get_center()).abs() - rect.size / 2
	return Vector2(maxf(d.x, 0), maxf(d.y, 0)).length() + minf(maxf(d.x, d.y), 0)
