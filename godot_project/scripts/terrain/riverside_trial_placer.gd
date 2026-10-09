extends Node3D
class_name RiversideTrialPlacer

## 태화강 국가정원·둔치 보도 시범 배치기. riverside_trial/placements.json의 위경도 배치를
## 현재 지도 범위 안에서 지형 높이에 맞춰 놓는다. 임포트 전 GLB도 실행 중 직접 읽는다.
## taehwagang_dunchi 지도는 RiversideAssetPlacer가 같은 배치를 담당하므로 건너뛴다.

const CATALOG := "res://assets/generated/riverside_trial/placements.json"
const SKIP_MAP_IDS := ["taehwagang_dunchi"]

@export var terrain_manager: Node3D
var load_complete := false
var placed_count := 0
var _models: Dictionary = {}

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or maps.selected_map.id in SKIP_MAP_IDS or not FileAccess.file_exists(CATALOG):
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
	print("RiversideTrialPlacer: ", placed_count, " placed")
	load_complete = true

func place_all(entries: Array, map) -> void:
	for entry in entries:
		if not entry is Dictionary or not _inside(entry.lonlat, map):
			continue
		var node := _instantiate(str(entry.get("scene", "")))
		if node == null:
			push_warning("둔치 시범 배치 건너뜀: " + str(entry.get("id", "?")))
			continue
		node.name = str(entry.get("id", "RiversideTrial"))
		var xz := _world_xz(entry.lonlat, map)
		var y := float(entry.get("absolute_y_m", 0.0))
		if str(entry.get("ground", "terrain")) == "terrain" and is_instance_valid(terrain_manager):
			y = terrain_manager.get_terrain_elevation(xz.x, xz.y)
		node.position = Vector3(xz.x, y + float(entry.get("y_offset_m", 0.0)), xz.y)
		node.rotation.y = deg_to_rad(float(entry.get("yaw_degrees", 0.0)))
		node.scale = Vector3.ONE * float(entry.get("scale", 1.0))
		add_child(node)
		placed_count += 1

func _instantiate(scene_path: String) -> Node3D:
	# 임포트된 씬이 있으면 사용하고, 없으면 같은 이름의 GLB를 실행 중 읽는다
	var glb := scene_path.get_basename() + ".glb"
	if ResourceLoader.exists(scene_path) and ResourceLoader.exists(glb):
		return (load(scene_path) as PackedScene).instantiate() as Node3D
	if not _models.has(glb):
		_models[glb] = _load_glb(glb)
	var packed: PackedScene = _models[glb]
	return null if packed == null else packed.instantiate() as Node3D

func _load_glb(path: String) -> PackedScene:
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	var root := document.generate_scene(state)
	if root == null:
		return null
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

static func _inside(lonlat: Array, map) -> bool:
	var lon := float(lonlat[0])
	var lat := float(lonlat[1])
	return lon >= map.bbox_west and lon <= map.bbox_east and lat >= map.bbox_south and lat <= map.bbox_north

static func _world_xz(lonlat: Array, map) -> Vector2:
	var size: float = map.world_size_meters
	var x := ((float(lonlat[0]) - map.bbox_west) / (map.bbox_east - map.bbox_west) - 0.5) * size
	var z := ((map.bbox_north - float(lonlat[1])) / (map.bbox_north - map.bbox_south) - 0.5) * size
	return Vector2(x, z)
