extends Node3D
class_name RiversideTrialPlacer

## 태화강 국가정원·둔치 보도 시범 배치기. riverside_trial/placements.json의 위경도 배치를
## 현재 지도 범위 안에서 지형 높이에 맞춰 놓는다. 임포트 전 GLB도 실행 중 직접 읽는다.
## taehwagang_dunchi 지도는 RiversideAssetPlacer가 같은 배치를 담당하므로 건너뛴다.

const CATALOG := "res://assets/generated/riverside_trial/placements.json"
const SKIP_MAP_IDS := ["taehwagang_dunchi"]
const ChainProfile = preload("res://scripts/terrain/riverside_chain_profile.gd")
## 지형 메시 LOD가 높이맵 표본보다 약간 높게 보간될 수 있어 두는 여유 높이
const PATH_CLEARANCE_M := 0.15
const OBJECT_CLEARANCE_M := 0.03

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
	var inside: Array = entries.filter(func(e): return e is Dictionary and _inside(e.lonlat, map))
	var profiles := _build_profiles(inside, map)
	for entry in inside:
		var node := _instantiate(str(entry.get("scene", "")))
		if node == null:
			push_warning("둔치 시범 배치 건너뜀: " + str(entry.get("id", "?")))
			continue
		node.name = str(entry.get("id", "RiversideTrial"))
		var xz := _world_xz(entry.lonlat, map)
		var yaw := deg_to_rad(float(entry.get("yaw_degrees", 0.0)))
		var pitch := 0.0
		var y := float(entry.get("absolute_y_m", 0.0))
		var profile = profiles.get(str(entry.get("chain", "")))
		if profile != null and entry.has("chain_index"):
			# 보도와 선형 부속물: 이웃과 공유하는 접속점 높이를 따라 기울인다
			var index := int(entry.chain_index)
			y = profile.segment_center_y(index)
			pitch = -atan(profile.segment_slope(index))
			yaw = profile.yaw()
		elif str(entry.get("ground", "terrain")) == "terrain" and is_instance_valid(terrain_manager):
			y = _footprint_max(xz, yaw, entry.get("footprint_half_m", [0.0, 0.0])) + OBJECT_CLEARANCE_M
		node.position = Vector3(xz.x, y + float(entry.get("y_offset_m", 0.0)), xz.y)
		node.rotation = Vector3(pitch, yaw, 0.0)
		node.scale = Vector3.ONE * float(entry.get("scale", 1.0))
		# 기울인 세그먼트의 수평 투영 길이가 줄어 생기는 접속 틈을 진행축 배율로 메운다
		node.scale.z /= cos(pitch)
		if profile != null and entry.has("chain_index"):
			node.scale.z *= profile.stretch
		add_child(node)
		placed_count += 1

func _build_profiles(entries: Array, map) -> Dictionary:
	var groups: Dictionary = {}
	for entry in entries:
		if str(entry.get("chain_role", "")) != "path":
			continue
		var chain := str(entry.chain)
		if not groups.has(chain):
			groups[chain] = []
		groups[chain].append(entry)
	var profiles: Dictionary = {}
	if not is_instance_valid(terrain_manager):
		return profiles
	var elevation := Callable(terrain_manager, "get_terrain_elevation")
	for chain in groups:
		var group: Array = groups[chain]
		var segments: Array = group.map(func(e): return {"xz": _world_xz(e.lonlat, map), "index": int(e.chain_index)})
		var profile = ChainProfile.new()
		profile.build(segments, float(group[0].yaw_degrees), float(group[0].segment_length_m), float(group[0].chain_half_width_m), PATH_CLEARANCE_M, elevation)
		profiles[chain] = profile
	return profiles

func _footprint_max(xz: Vector2, yaw: float, half: Array) -> float:
	# 회전된 바닥면의 모서리·변 중점·중심 중 가장 높은 지형에 맞춰 묻히지 않게 한다
	var axis_x := Vector2(cos(yaw), -sin(yaw)) * float(half[0])
	var axis_z := Vector2(sin(yaw), cos(yaw)) * float(half[1])
	var best := -INF
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var p: Vector2 = xz + axis_x * sx + axis_z * sz
			best = maxf(best, float(terrain_manager.get_terrain_elevation(p.x, p.y)))
	return best

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
	var x: float = ((float(lonlat[0]) - map.bbox_west) / (map.bbox_east - map.bbox_west) - 0.5) * size
	var z: float = ((map.bbox_north - float(lonlat[1])) / (map.bbox_north - map.bbox_south) - 0.5) * size
	return Vector2(x, z)
