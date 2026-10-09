extends Node3D
class_name RailwayWorldManager

const TrackBuilder = preload("res://scripts/terrain/railway_track_builder.gd")
const Route = preload("res://scripts/terrain/railway_route.gd")
const TrainService = preload("res://scripts/terrain/railway_train_service.gd")
const Landmarks = preload("res://scripts/terrain/railway_landmark_manager.gd")
const Alignment = preload("res://scripts/terrain/railway_alignment_catalog.gd")
const Tunnels = preload("res://scripts/terrain/railway_tunnel_world_manager.gd")
const Formation = preload("res://scripts/terrain/railway_formation_builder.gd")
const ChunkStream = preload("res://scripts/terrain/railway_chunk_stream.gd")
const Quality = preload("res://scripts/models/render_quality_profile.gd")
var _alignment: RefCounted
var landmarks: Node3D

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
	_alignment = Alignment.new()
	if _alignment.data.is_empty():
		load_error = "철도 종단 및 터널 배치 자산을 읽지 못했습니다."
		return
	var profiles := {}
	for profile in settings.services:
		profiles[profile.id] = profile
	var count := 0
	landmarks = Landmarks.new()
	landmarks.name = "RailwayLandmarks"
	add_child(landmarks)
	landmarks.setup(map_config,terrain)
	# 열차 경로의 높이와 세분화 구간을 먼저 준비한다.
	for track in network.tracks:
		_project_track(track, map_config, terrain)
	_start_services(network, settings, profiles, map_config, terrain, player)
	var stream := ChunkStream.new()
	stream.name = "RailwayChunkStream"
	add_child(stream)
	stream.configure(player, terrain)
	for track in network.tracks:
		var points := _project_track(track, map_config, terrain)
		var structure: Dictionary = track.duplicate()
		structure.custom_bridge = landmarks.custom_bridge(int(track.osm_id))
		if structure.custom_bridge:
			landmarks.place_bridge(track,points,terrain)
		for chunk in _chunks(points):
			stream.append(chunk, profiles[track.service], structure)
			count += 1
			if count % 8 == 0:
				await get_tree().process_frame
				if not is_inside_tree():
					return
	await stream.prepare_initial()
	if not is_inside_tree():
		return
	var tunnels := Tunnels.new()
	tunnels.name = "RailwayTunnels"
	add_child(tunnels)
	tunnels.configure(_alignment,player)
	load_complete = true

func _start_services(network: Dictionary, settings: Dictionary, profiles: Dictionary, map_config, terrain: Node3D, player: Node3D) -> void:
	for data in network.routes:
		var route := Route.new()
		var projected := _project_route(data.points, data.stops, map_config, terrain)
		if data.service == "ktx":
			var placement_route := Route.new()
			placement_route.configure(projected.points,projected.stops)
			for stop in placement_route.stops:
				if stop.name == "울산":
					landmarks.place_ulsan_interface(landmarks.slice(placement_route,stop.distance-24,stop.distance+24),terrain)
		route.configure(projected.points, projected.stops)
		var opposite := Route.new()
		var reverse_projected := _project_route(data.opposite_points, data.opposite_stops, map_config, terrain)
		opposite.configure(reverse_projected.points, reverse_projected.stops)
		var service := TrainService.new()
		service.name = str(data.service) + "_service"
		service.configure(route, profiles[data.service], player, float(settings.time_scale), opposite, minf(float(settings.render_distance_m), float(Quality.current().view_distance)))
		add_child(service)
		services.append(service)
	print("[RailwayWorldManager] 열차 운행 시작: %d개 노선, 표시 거리 %.0fm" % [services.size(), float(settings.render_distance_m)])

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
	if _alignment==null:
		_alignment = Alignment.new()
	var record: Dictionary = _alignment.tracks.get(int(track.osm_id),{})
	var points: PackedVector3Array = _alignment.projected(record)
	var indices: Array = record.get("original_indices",[])
	for i in range(indices.size()):
		_elevations[_key(track.points[i])] = points[int(indices[i])].y
		if i>0:
			_segments[_key(track.points[i-1])+"|"+_key(track.points[i])] = points.slice(int(indices[i-1]),int(indices[i])+1)
	return points

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
