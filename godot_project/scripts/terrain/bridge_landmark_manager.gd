extends Node3D
class_name BridgeLandmarkManager

const Builder = preload("res://scripts/terrain/bridge_landmark_builder.gd")
const SPEC_PATH := "res://assets/generated/taehwa_bridges.json"
var replaced_osm_ids: Dictionary = {}

func setup(map_config, terrain: Node3D) -> void:
	if map_config == null or map_config.bbox_west > 129.27 or map_config.bbox_east < 129.41:
		return
	if map_config.bbox_south > 35.51 or map_config.bbox_north < 35.56:
		return
	if not FileAccess.file_exists(SPEC_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	if not data is Dictionary:
		return
	for spec in data.get("bridges", []):
		var curve := Curve3D.new()
		for p in spec.get("geometry", []):
			var x: float = (float(p.lon) - map_config.bbox_west) / (map_config.bbox_east - map_config.bbox_west) - 0.5
			var z: float = (map_config.bbox_north - float(p.lat)) / (map_config.bbox_north - map_config.bbox_south) - 0.5
			curve.add_point(Vector3(x, 0.0, z) * map_config.world_size_meters)
		if curve.point_count < 2:
			continue
		add_child(Builder.build(spec, curve, terrain))
		for osm_id in spec.osm_ids:
			replaced_osm_ids[str(osm_id)] = true

func replaces_road(road: Dictionary) -> bool:
	return replaced_osm_ids.has(str(road.get("osm_id", "")))
