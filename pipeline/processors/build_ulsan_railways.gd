extends SceneTree

var vertices: Dictionary = {}
var adjacency: Dictionary = {}
var geographic_points: Dictionary = {}

func _initialize() -> void:
	var raw: Dictionary = _read("res://../data/raw/ulsan_metro_80km/railway/osm_railways.json")
	var stations: Dictionary = _read("res://../data/raw/ulsan_metro_80km/railway/osm_stations.json")
	var settings: Dictionary = _read("res://../config/ulsan_railway_services.json")
	if raw.is_empty() or stations.is_empty() or settings.is_empty():
		quit(1)
		return
	var output := {"schema_version": 1, "source": "OpenStreetMap / Overpass", "license": "ODbL-1.0", "source_timestamp": raw.get("osm3s", {}).get("timestamp_osm_base", ""), "tracks": [], "routes": []}
	for service in settings.services:
		vertices.clear()
		adjacency.clear()
		geographic_points.clear()
		for way in raw.elements:
			var tags: Dictionary = way.get("tags", {})
			if not str(tags.get("name", "")) in service.track_names or tags.has("service"):
				continue
			var points: Array = []
			var previous := ""
			for p in way.get("geometry", []):
				var key := "%.7f,%.7f" % [p.lon, p.lat]
				points.append([p.lon, p.lat])
				vertices[key] = Vector2(p.lon, p.lat)
				geographic_points[key] = [p.lon, p.lat]
				if not adjacency.has(key):
					adjacency[key] = {}
				if not previous.is_empty() and previous != key:
					var distance := _meters(vertices[previous], vertices[key])
					adjacency[previous][key] = distance
					adjacency[key][previous] = distance
				previous = key
			if points.size() >= 2:
				output.tracks.append({"osm_id": way.id, "service": service.id, "points": points, "bridge": tags.get("bridge", "no") != "no", "tunnel": tags.get("tunnel", "no") != "no", "layer": int(tags.get("layer", "0"))})
		var station_points := _stations(stations, service.station_names)
		var anchor: Vector2 = station_points.get(service.anchor_station, Vector2(129.138, 35.551))
		var component := _component(_nearest(anchor, vertices.keys()))
		if component.size() < 2:
			push_error("철도 연결망 없음: " + service.id)
			quit(1)
			return
		var ordered: Array = component.duplicate()
		ordered.sort_custom(func(a, b): return vertices[a].y < vertices[b].y)
		var start: String = ordered[0]
		var finish: String = ordered[-1]
		if not str(service.terminus_station).is_empty():
			finish = _nearest(station_points[service.terminus_station], component)
		var path := _shortest_path(start, finish)
		var route_points: Array = []
		for key in path:
			route_points.append(geographic_points[key])
		if path.size() < 2:
			push_error("철도 운행 경로 연결 실패: " + service.id)
			quit(1)
			return
		var stops: Array = []
		for station_name in station_points:
			var nearest := _nearest(station_points[station_name], path)
			if _meters(station_points[station_name], vertices[nearest]) < 600.0:
				stops.append({"name": station_name, "point_index": path.find(nearest)})
		output.routes.append({"service": service.id, "points": route_points, "stops": stops, "component_vertices": component.size()})
		print("[철도 생성] ", service.id, " 경로 정점=", path.size(), " 역=", stops.size())
		# 반대 방향은 첫 경로의 간선을 제외한 실제 병행 선로에서 찾는다.
		for index in range(1, path.size()):
			adjacency[path[index - 1]].erase(path[index])
			adjacency[path[index]].erase(path[index - 1])
		var candidates: Array = []
		for key in vertices:
			if not key in path and not adjacency[key].is_empty():
				candidates.append(key)
		var opposite_component := _component(_nearest(anchor, candidates))
		var opposite_ordered: Array = opposite_component.duplicate()
		opposite_ordered.sort_custom(func(a, b): return vertices[a].y < vertices[b].y)
		var opposite_start: String = opposite_ordered[0]
		var opposite_finish: String = opposite_ordered[-1]
		if not str(service.terminus_station).is_empty():
			opposite_finish = _nearest(station_points[service.terminus_station], opposite_component)
		var opposite_path := _shortest_path(opposite_start, opposite_finish)
		var opposite_points: Array = []
		for key in opposite_path:
			opposite_points.append(geographic_points[key])
		var opposite_stops: Array = []
		for station_name in station_points:
			var nearest := _nearest(station_points[station_name], opposite_path)
			if not nearest.is_empty() and _meters(station_points[station_name], vertices[nearest]) < 600.0:
				opposite_stops.append({"name": station_name, "point_index": opposite_path.find(nearest)})
		output.routes[-1]["opposite_points"] = opposite_points
		output.routes[-1]["opposite_stops"] = opposite_stops
		print("[철도 생성] ", service.id, " 반대 선로 정점=", opposite_path.size())
	var destination := "res://assets/generated/railway"
	DirAccess.make_dir_recursive_absolute(destination)
	_write(destination + "/network.json", output)
	_write(destination + "/services.json", settings)
	var manifest: Dictionary = _read("res://assets/generated/manifest.json")
	for name in ["network", "services"]:
		var path: String = destination + "/" + name + ".json"
		manifest.assets["ulsan_railway_" + name] = {"file_path": path, "sha256": FileAccess.get_sha256(path), "type": "railway_" + name, "bbox": {"south": 35.1841, "north": 35.9049, "west": 128.8125667, "east": 129.6984333}, "min_elevation": null, "max_elevation": null, "resolution": "OSM 원본 벡터", "elevation_note": "실행 시 지도 지형에서 표고 샘플링", "source": output.source, "license": output.license}
	_write("res://assets/generated/manifest.json", manifest)
	quit()

func _stations(raw: Dictionary, names: Array) -> Dictionary:
	var result := {}
	for element in raw.elements:
		var name: String = str(element.get("tags", {}).get("name", "")).trim_suffix("역")
		if name in names:
			var p: Dictionary = element.get("center", element)
			result[name] = Vector2(p.lon, p.lat)
	return result

func _component(start: String) -> Array:
	var visited := {start: true}
	var queue: Array = [start]
	var cursor := 0
	while cursor < queue.size():
		var key: String = queue[cursor]
		cursor += 1
		for neighbor in adjacency[key]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return queue

func _shortest_path(start: String, finish: String) -> Array:
	var distance := {start: 0.0}
	var parent := {}
	var pending := {start: true}
	while not pending.is_empty():
		var current: String = pending.keys()[0]
		for key in pending:
			if distance[key] < distance[current]:
				current = key
		pending.erase(current)
		if current == finish:
			break
		for neighbor in adjacency[current]:
			var cost: float = distance[current] + adjacency[current][neighbor]
			if cost < float(distance.get(neighbor, INF)):
				distance[neighbor] = cost
				parent[neighbor] = current
				pending[neighbor] = true
	if not distance.has(finish):
		return []
	var path: Array = [finish]
	while path[-1] != start:
		path.append(parent[path[-1]])
	path.reverse()
	return path

func _nearest(point: Vector2, keys: Array) -> String:
	var best := ""
	var distance := INF
	for key in keys:
		var d := _meters(point, vertices[key])
		if d < distance:
			distance = d
			best = key
	return best

func _meters(a: Vector2, b: Vector2) -> float:
	return Vector2((a.x - b.x) * 90500.0, (a.y - b.y) * 111000.0).length()

func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("파일을 읽을 수 없습니다: " + path)
		return {}
	var value = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
