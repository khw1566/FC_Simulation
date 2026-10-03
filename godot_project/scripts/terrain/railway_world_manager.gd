extends Node3D
class_name RailwayWorldManager

const TrackBuilder = preload("res://scripts/terrain/railway_track_builder.gd")
const Route = preload("res://scripts/terrain/railway_route.gd")
const TrainService = preload("res://scripts/terrain/railway_train_service.gd")

var load_complete := false
var load_error := ""
var services: Array[Node3D] = []
var _elevations: Dictionary = {}
var _segments: Dictionary = {}

func setup(map_config, terrain: Node3D, player: Node3D) -> void:
	if map_config.id != "ulsan_metro_80km":
		load_complete = true
		return
	var network := _read("res://assets/generated/railway/network.json")
	var settings := _read("res://assets/generated/railway/services.json")
	if network.is_empty() or settings.is_empty():
		load_error = "울산 철도 자산을 읽지 못했습니다."
		push_error(load_error)
		return
	var profiles := {}
	for profile in settings.services:
		profiles[profile.id] = profile
	var count := 0
	for track in network.tracks:
		var points := _project_track(track, map_config, terrain)
		for chunk in _chunks(points):
			var node := TrackBuilder.build(chunk, profiles[track.service], track, float(settings.render_distance_m))
			node.name = "Rail_%s_%s_%d" % [track.service, str(track.osm_id), count]
			add_child(node)
			count += 1
			if count % 8 == 0:
				await get_tree().process_frame
				if not is_inside_tree():
					return
	for data in network.routes:
		var route := Route.new()
		var projected := _project_route(data.points, data.stops, map_config, terrain)
		route.configure(projected.points, projected.stops)
		var opposite := Route.new()
		var reverse_projected := _project_route(data.opposite_points, data.opposite_stops, map_config, terrain)
		opposite.configure(reverse_projected.points, reverse_projected.stops)
		var service := TrainService.new()
		service.name = str(data.service) + "_service"
		service.configure(route, profiles[data.service], player, float(settings.time_scale), opposite)
		add_child(service)
		services.append(service)
	load_complete = true

func _chunks(points: PackedVector3Array) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	var chunk := PackedVector3Array()
	var distance := 0.0
	for point in points:
		if not chunk.is_empty():
			distance += chunk[-1].distance_to(point)
		chunk.append(point)
		if distance >= 500.0:
			result.append(chunk)
			chunk = PackedVector3Array([point])
			distance = 0.0
	if chunk.size() > 1:
		result.append(chunk)
	return result

func _project_track(track: Dictionary, map_config, terrain: Node3D) -> PackedVector3Array:
	var original := PackedVector3Array()
	for coordinate in track.points:
		original.append(_project(coordinate, map_config, terrain))
	var structured: bool = bool(track.bridge) or bool(track.tunnel)
	var cumulative := PackedFloat64Array([0.0])
	for index in range(1, original.size()):
		cumulative.append(cumulative[-1] + Vector2(original[index].x - original[index - 1].x, original[index].z - original[index - 1].z).length())
	var result := PackedVector3Array()
	for index in original.size():
		var point := original[index]
		if structured:
			point.y = lerpf(original[0].y, original[-1].y, cumulative[index] / maxf(0.01, cumulative[-1]))
			if track.bridge:
				point.y += 6.0
		point.y += 0.25
		_elevations[_key(track.points[index])] = point.y
		if index > 0:
			var previous := result[-1]
			var segment := PackedVector3Array([previous])
			var steps: int = maxi(1, ceili(previous.distance_to(point) / 25.0))
			for step in range(1, steps):
				var sample := previous.lerp(point, float(step) / steps)
				if not structured and is_instance_valid(terrain):
					sample.y = float(terrain.call("get_terrain_elevation", sample.x, sample.z)) + 0.25
				result.append(sample)
				segment.append(sample)
			segment.append(point)
			_segments[_key(track.points[index - 1]) + "|" + _key(track.points[index])] = segment
		result.append(point)
	return result

func _project_route(coordinates: Array, stations: Array, map_config, terrain: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	var index_map := {}
	for index in coordinates.size():
		if index == 0:
			var point := _project(coordinates[index], map_config, terrain)
			point.y = float(_elevations.get(_key(coordinates[index]), point.y))
			points.append(point + Vector3.UP * 0.12)
		else:
			var key: String = _key(coordinates[index - 1]) + "|" + _key(coordinates[index])
			var reverse_key: String = _key(coordinates[index]) + "|" + _key(coordinates[index - 1])
			var segment: PackedVector3Array = _segments.get(key, PackedVector3Array())
			if segment.is_empty() and _segments.has(reverse_key):
				segment = _segments[reverse_key].duplicate()
				segment.reverse()
			for step in range(1, segment.size()):
				points.append(segment[step] + Vector3.UP * 0.12)
		index_map[index] = points.size() - 1
	var remapped: Array = []
	for station in stations:
		remapped.append({"name": station.name, "point_index": index_map[int(station.point_index)]})
	return {"points": points, "stops": remapped}

func _project(coordinate: Array, map_config, terrain: Node3D) -> Vector3:
	var x: float = ((float(coordinate[0]) - map_config.bbox_west) / (map_config.bbox_east - map_config.bbox_west) - 0.5) * map_config.world_size_meters
	var z: float = ((map_config.bbox_north - float(coordinate[1])) / (map_config.bbox_north - map_config.bbox_south) - 0.5) * map_config.world_size_meters
	var y := 0.0
	if is_instance_valid(terrain):
		y = float(terrain.call("get_terrain_elevation", x, z))
	return Vector3(x, y, z)

func _key(coordinate: Array) -> String:
	return "%.7f,%.7f" % [coordinate[0], coordinate[1]]

func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}
