extends RefCounted
class_name RailwayTimetable

var phases: Array[Dictionary] = []
var duration := 0.0
var route_length := 0.0

func configure(route, profile: Dictionary, reverse: bool) -> void:
	phases.clear()
	duration = 0.0
	route_length = route.length
	var stops: Array[float] = [0.0]
	for station in route.stops:
		var distance: float = route_length - station.distance if reverse else station.distance
		if distance > 1.0 and distance < route_length - 1.0:
			stops.append(distance)
	stops.append(route_length)
	stops.sort()
	for index in range(1, stops.size()):
		var segment: float = stops[index] - stops[index - 1]
		if segment <= 0.01:
			continue
		var acceleration: float = maxf(0.01, float(profile.acceleration_mps2))
		var speed: float = minf(float(profile.speed_mps), sqrt(segment * acceleration))
		var ramp: float = speed / acceleration
		var cruise: float = maxf(0.0, (segment - speed * ramp) / speed)
		var travel: float = ramp * 2.0 + cruise
		phases.append({"start": duration, "end": duration + travel, "distance": stops[index - 1], "length": segment, "ramp": ramp, "cruise": cruise, "speed": speed, "acceleration": acceleration})
		duration += travel
		if index < stops.size() - 1:
			phases.append({"start": duration, "end": duration + float(profile.dwell_seconds), "distance": stops[index], "length": 0.0})
			duration += float(profile.dwell_seconds)

func distance_at(age: float) -> float:
	for phase in phases:
		if age <= phase.end:
			var time: float = maxf(0.0, age - phase.start)
			if phase.length == 0.0:
				return phase.distance
			if time < phase.ramp:
				return phase.distance + 0.5 * phase.acceleration * time * time
			if time < phase.ramp + phase.cruise:
				return phase.distance + 0.5 * phase.speed * phase.ramp + phase.speed * (time - phase.ramp)
			var remaining: float = maxf(0.0, phase.end - age)
			return phase.distance + phase.length - 0.5 * phase.acceleration * remaining * remaining
	return route_length
