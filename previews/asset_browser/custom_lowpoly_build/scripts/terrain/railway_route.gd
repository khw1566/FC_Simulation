extends RefCounted
class_name RailwayRoute

var points := PackedVector3Array()
var distances := PackedFloat64Array()
var stops: Array[Dictionary] = []
var length := 0.0

func configure(projected: PackedVector3Array, station_data: Array) -> void:
	points = projected
	distances.clear()
	length = 0.0
	for index in points.size():
		if index > 0:
			length += points[index].distance_to(points[index - 1])
		distances.append(length)
	stops.clear()
	for station in station_data:
		var index: int = clampi(int(station.point_index), 0, points.size() - 1)
		stops.append({"name": station.name, "distance": distances[index]})
	stops.sort_custom(func(a, b): return a.distance < b.distance)

func sample(distance: float, lateral: float = 0.0) -> Transform3D:
	var d := clampf(distance, 0.0, length)
	var low := 0
	var high := distances.size() - 1
	while low + 1 < high:
		var mid: int = (low + high) / 2
		if distances[mid] <= d:
			low = mid
		else:
			high = mid
	var span: float = maxf(0.001, distances[high] - distances[low])
	var tangent := (points[high] - points[low]).normalized()
	if tangent.length_squared() < 0.1:
		tangent = Vector3.FORWARD
	var side := tangent.cross(Vector3.UP).normalized()
	var origin := points[low].lerp(points[high], (d - distances[low]) / span) + side * lateral
	var basis := Basis.looking_at(tangent, Vector3.UP)
	return Transform3D(basis, origin)
