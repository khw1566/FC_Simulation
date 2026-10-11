extends RefCounted
class_name VesselRoute

## 해수 안전 영역 안에서 정박과 왕복 운항을 반복하는 경로.
var points: Array[Vector3] = []
var distances: Array[float] = [0.0]
var length: float = 0.0
var speed: float = 1.0
var harbor_dwell: float = 90.0
var offshore_dwell: float = 20.0
var phase: float = 0.0
var duration: float = 1.0
var moored := false
var heading := 0.0

func configure(entry: Dictionary, sea_level: float, settings: Dictionary) -> void:
	moored = entry.get("mode", "sailing") == "moored"
	heading = float(entry.get("heading_radians", 0.0))
	for p in entry.points_xz:
		points.append(Vector3(float(p[0]), sea_level, float(p[1])))
		if points.size() > 1:
			length += points[-2].distance_to(points[-1])
			distances.append(length)
	speed = maxf(float(entry.speed_mps), 0.1)
	harbor_dwell = float(settings.get("harbor_dwell_seconds", 90.0))
	offshore_dwell = float(settings.get("offshore_dwell_seconds", 20.0))
	duration = harbor_dwell + offshore_dwell + 2.0 * length / speed
	phase = float(entry.get("initial_phase", 0.0)) * duration

func sample(elapsed: float) -> Transform3D:
	if moored and not points.is_empty():
		return Transform3D(Basis(Vector3.UP, heading), points[0])
	if points.size() < 2:
		return Transform3D.IDENTITY
	var time := fposmod(elapsed + phase, duration)
	var distance := 0.0
	var direction := 1.0
	var travel := length / speed
	if time > harbor_dwell + travel + offshore_dwell:
		direction = -1.0
		distance = length - (time - harbor_dwell - travel - offshore_dwell) * speed
	elif time > harbor_dwell + travel:
		distance = length
	elif time > harbor_dwell:
		distance = (time - harbor_dwell) * speed
	distance = clampf(distance, 0.0, length)
	var segment := 0
	while segment < points.size() - 2 and distances[segment + 1] < distance:
		segment += 1
	var a := points[segment]
	var b := points[segment + 1]
	var weight := (distance - distances[segment]) / maxf(a.distance_to(b), 0.001)
	return Transform3D(Basis.looking_at((b-a).normalized() * direction, Vector3.UP), a.lerp(b, weight))

func moving_speed(elapsed: float) -> float:
	if moored:
		return 0.0
	var time := fposmod(elapsed + phase, duration)
	var travel := length / speed
	if (time > harbor_dwell and time < harbor_dwell + travel) or time > harbor_dwell + travel + offshore_dwell:
		return speed
	return 0.0
