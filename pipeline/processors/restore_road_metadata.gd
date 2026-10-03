extends SceneTree

func _initialize() -> void:
	var map_dir := "res://assets/maps/ulsan_metro_60km"
	var raw_path := ProjectSettings.globalize_path("res://../data/raw/ulsan_metro_60km/highways/overpass_ulsan_metro_highways.json")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(raw_path))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_dir + "/buildings_and_roads.json"))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_dir + "/map_meta.json"))
	var nodes: Dictionary = {}
	var roads: Dictionary = {}
	for element in raw.elements:
		if element.type == "node":
			nodes[int(element.id)] = element
	for road in data.roads:
		roads[str(road.id)] = road
	var entries: Dictionary = {}
	var sequence: int = 0
	var changed: int = 0
	for way in raw.elements:
		if way.type != "way":
			continue
		var projected: Array[Vector2] = []
		for id in way.nodes:
			if nodes.has(int(id)):
				var p: Dictionary = nodes[int(id)]
				projected.append(Vector2(((float(p.lon) - float(meta.bbox.west)) / (float(meta.bbox.east) - float(meta.bbox.west)) - 0.5) * float(meta.world_size_meters), ((float(meta.bbox.north) - float(p.lat)) / (float(meta.bbox.north) - float(meta.bbox.south)) - 0.5) * float(meta.world_size_meters)))
		if projected.size() < 2:
			continue
		sequence += 1
		var id := "rd_metro_%d" % sequence
		if not roads.has(id):
			continue
		var road: Dictionary = roads[id]
		var matches: bool = projected.size() == road.points.size()
		if matches:
			for i in range(projected.size()):
				if projected[i].distance_to(Vector2(float(road.points[i][0]), float(road.points[i][2]))) > 0.06:
					matches = false
					break
		if not matches:
			continue
		var tags: Dictionary = way.get("tags", {})
		var width: float = road.get("width", 8)
		var method: String = "기존 폭 유지"
		var raw_width: String = str(tags.get("width", "")).trim_suffix(" m").strip_edges()
		var lanes: String = str(tags.get("lanes", ""))
		var one_way: bool = str(tags.get("oneway", "no")) in ["yes", "1", "true", "-1"]
		if raw_width.is_valid_float() and raw_width.to_float() >= 2 and raw_width.to_float() <= 80:
			width = raw_width.to_float()
			method = "OSM width"
		elif lanes.is_valid_int() and lanes.to_int() >= 1 and lanes.to_int() <= 12:
			width = lanes.to_int() * 3.5 + 1.5
			method = "OSM 차로 수 기반 추정"
		elif one_way:
			width = maxf(4, width * 0.55)
			method = "일방통행 분리 차도 폭 추정"
		if not is_equal_approx(width, float(road.width)):
			changed += 1
		entries[id] = {"points_sha256": JSON.stringify(road.points).sha256_text(), "osm_id": int(way.id), "width": width, "layer": str(tags.get("layer", "0")), "oneway": one_way, "width_basis": method}
	var output_path := map_dir + "/road_metadata.json"
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	output.store_string(JSON.stringify({"source": "기존 OSM 캐시, 전체 좌표 대조 후 복원", "attribution": "© OpenStreetMap contributors, ODbL", "entries": entries}, "  "))
	output.close()
	var entry := {"file_name": "road_metadata.json", "category": "road_metadata", "sha256": FileAccess.get_sha256(output_path), "size_bytes": FileAccess.open(output_path, FileAccess.READ).get_length(), "bbox": meta.bbox, "resolution": {"type": "road_attributes", "record_count": entries.size()}, "elevation": {"min_meters": meta.min_elevation, "max_meters": meta.max_elevation}}
	for manifest_path in [map_dir + "/manifest.json", "res://assets/generated/manifest.json"]:
		entry["file_path"] = output_path
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		manifest["indexed_at" if manifest_path.begins_with(map_dir) else "last_updated"] = Time.get_datetime_string_from_system()
		manifest.assets["road_metadata.json" if manifest_path.begins_with(map_dir) else "ulsan_road_metadata"] = entry
		var file := FileAccess.open(manifest_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "  "))
		file.close()
	print("도로 속성 복원: ", entries.size(), " / 폭 수정: ", changed)
	quit(0)
