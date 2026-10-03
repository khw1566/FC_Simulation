extends Node3D
class_name LandmarkManager

const GeoConverter = preload("res://scripts/core/geo_coordinate_converter.gd")
const BeaconClass = preload("res://scripts/terrain/landmark_beacon.gd")

@export var player_node: Node3D
var beacons: Array = []

func _ready() -> void:
	load_and_spawn_landmarks()

func load_and_spawn_landmarks() -> void:
	var path: String = ""
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			path = svc.selected_map.landmarks_path
			GeoConverter.configure_bounds(
				svc.selected_map.bbox_south,
				svc.selected_map.bbox_north,
				svc.selected_map.bbox_west,
				svc.selected_map.bbox_east,
				svc.selected_map.world_size_meters
			)

	if path.is_empty() or not FileAccess.file_exists(path):
		var default_path := "res://assets/maps/kanmon_straits/landmarks.json"
		if FileAccess.file_exists(default_path):
			path = default_path
		else:
			path = "res://../config/key_landmarks.json"

	if not FileAccess.file_exists(path):
		push_warning("[LandmarkManager] Key landmarks file not found: " + path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var json_res = JSON.parse_string(file.get_as_text())
	if typeof(json_res) != TYPE_ARRAY:
		return

	for item in json_res:
		var id: String = item.get("id", "")
		var name_ko: String = item.get("name_ko", "")
		var lat: float = float(item.get("lat", 0.0))
		var lon: float = float(item.get("lon", 0.0))
		var alt: float = float(item.get("altitude_meters", 0.0))
		var pole_h: float = float(item.get("pole_height", 100.0))

		# WGS84 위경도 -> 미터법 월드 좌표 변환
		var world_pos: Vector3 = GeoConverter.geo_to_world(lat, lon, alt)

		var beacon = BeaconClass.new()
		add_child(beacon)
		beacon.setup(id, name_ko, world_pos, pole_h)
		beacons.append(beacon)

	print("[LandmarkManager] Spawned ", beacons.size(), " landmark distance beacons.")

func _physics_process(_delta: float) -> void:
	if not player_node:
		return
	var p_pos := player_node.global_position
	for b in beacons:
		b.update_distance(p_pos)
