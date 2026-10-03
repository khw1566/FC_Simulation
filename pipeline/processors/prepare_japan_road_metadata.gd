extends SceneTree

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../data/raw/infrastructure/kanmon_straits_infra.json"))
	var ways: Dictionary = {}
	for element in source.elements:
		if element.type == "way" and element.has("tags"):
			ways[str(element.id)] = element.tags
	var path := "res://assets/maps/kanmon_straits/buildings_and_roads.json"
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var entries: Dictionary = {}
	for road in vectors.roads:
		var tags: Dictionary = ways.get(str(road.id), {})
		var width: float = float(road.get("width", 0))
		if str(tags.get("width", "")).is_valid_float():
			width = float(tags.width)
		if width <= 0:
			var defaults := {"motorway": 12.0, "trunk": 10.0, "primary": 9.0, "secondary": 8.0, "tertiary": 7.0, "residential": 6.0, "service": 4.0, "footway": 1.8, "path": 1.5, "steps": 1.5, "cycleway": 2.5}
			width = defaults.get(str(road.get("type", "")), 6.0)
		var entry := {"points_sha256": JSON.stringify(road.points).sha256_text(), "osm_id": str(road.id), "width": clampf(width, 1.0, 40.0), "layer": int(tags.get("layer", 0)),
			"bridge": tags.get("bridge", road.get("is_bridge", false)), "tunnel": tags.get("tunnel", road.get("is_tunnel", false)), "surface": tags.get("surface", ""), "structure_tags_verified": not tags.is_empty()}
		entries[str(road.id)] = entry
	var output := FileAccess.open("res://assets/maps/kanmon_straits/road_metadata.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"entries": entries, "source": "OpenStreetMap retained infrastructure", "source_sha256": FileAccess.get_sha256(path)}, "  "))
	print("일본 원본 도로 속성 복원: ", entries.size())
	quit(0)
