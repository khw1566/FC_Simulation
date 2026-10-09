extends Node3D
class_name RiversideAssetPlacer

## 태화강 둔치 지도 전용 에셋 배치기. placements.json의 씬을 지형 높이에 맞춰 배치한다.
## 다른 지도에서는 아무 것도 하지 않는다.

const MAP_ID := "taehwagang_dunchi"
const CATALOG := "res://assets/maps/taehwagang_dunchi/placements.json"

@export var terrain_manager: Node3D
var load_complete := false
var placed_count := 0

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or maps.selected_map.id != MAP_ID or not FileAccess.file_exists(CATALOG):
		load_complete = true
		return
	while is_instance_valid(terrain_manager) and not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if catalog is Dictionary:
		place_all(catalog.get("placements", []), maps.selected_map)
	load_complete = true

func place_all(entries: Array, map) -> void:
	for entry in entries:
		if not entry is Dictionary or not ResourceLoader.exists(str(entry.get("scene", ""))):
			push_warning("둔치 배치 건너뜀: " + str(entry.get("id", "?")))
			continue
		var node := (load(str(entry.scene)) as PackedScene).instantiate() as Node3D
		if node == null:
			continue
		node.name = str(entry.get("id", "RiversideAsset"))
		var xz := world_xz(entry, map)
		var y := float(entry.get("absolute_y_m", 0.0))
		if str(entry.get("ground", "terrain")) == "terrain":
			y = terrain_manager.get_terrain_elevation(xz.x, xz.y)
		node.position = Vector3(xz.x, y + float(entry.get("y_offset_m", 0.0)), xz.y)
		node.rotation.y = deg_to_rad(float(entry.get("yaw_degrees", 0.0)))
		node.scale = Vector3.ONE * float(entry.get("scale", 1.0))
		add_child(node)
		placed_count += 1

static func world_xz(entry: Dictionary, map) -> Vector2:
	if entry.has("world_xz"):
		return Vector2(float(entry.world_xz[0]), float(entry.world_xz[1]))
	var lon := float(entry.lonlat[0])
	var lat := float(entry.lonlat[1])
	var size: float = map.world_size_meters
	var x := ((lon - map.bbox_west) / (map.bbox_east - map.bbox_west) - 0.5) * size
	var z := ((map.bbox_north - lat) / (map.bbox_north - map.bbox_south) - 0.5) * size
	return Vector2(x, z)
