extends Node3D
class_name RiversideTrialPlacer

## 태화강 둔치 보도 배치기. riverside_trial/paths.json의 OSM 보행로 체인과 placements.json의 시설물을
## 현재 지도 범위 안에서 지형 높이에 맞춰 놓는다. 같은 씬은 MultiMesh로 묶고, 임포트 전 GLB도 직접 읽는다.
## taehwagang_dunchi 지도는 RiversideAssetPlacer가 담당하므로 건너뛴다.

## 체인 형식 보도 파일: 둔치 보도망, 언양~시내 태화강 자전거길
const PATH_FILES := ["res://assets/generated/riverside_trial/paths.json", "res://assets/generated/riverside_trial/cycleway.json"]
const CATALOG := "res://assets/generated/riverside_trial/placements.json"
const SKIP_MAP_IDS := ["taehwagang_dunchi"]
const PathProfile = preload("res://scripts/terrain/riverside_path_profile.gd")
const Batcher = preload("res://scripts/terrain/riverside_instance_batcher.gd")
const SurfaceSampler = preload("res://scripts/terrain/riverside_surface_sampler.gd")
## 보도 조각 바닥의 지면 기준 높이. 보도 표면은 바닥보다 0.15 m 높아 바닥을 조금 묻어도 표면은 지면 위에 남는다
const PATH_CLEARANCE_M := -0.06
const OBJECT_CLEARANCE_M := 0.02
## 굽은 접속부의 바깥쪽 틈을 덮도록 조각 양 끝을 늘리는 길이
const SEGMENT_OVERLAP_M := 0.6
## 같은 체인의 굽은 접속부에서 겹치는 이웃 조각끼리 깜박이지 않도록 번갈아 주는 높이 차
const ALTERNATE_LIFT_M := 0.012
## 서로 교차하는 다른 체인끼리 겹쳐 깜박이지 않도록 체인마다 주는 높이 단 간격(단 정보가 없을 때 단 수)
const CHAIN_TIERS := 5
const CHAIN_TIER_M := 0.025

@export var terrain_manager: Node3D
var load_complete := false
var placed_count := 0
var _models: Dictionary = {}
var _surface

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or maps.selected_map.id in SKIP_MAP_IDS or not is_instance_valid(terrain_manager):
		load_complete = true
		return
	while not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_surface = SurfaceSampler.new(terrain_manager)
	var instances: Dictionary = {}
	for path_file in PATH_FILES:
		var data := _read_json(path_file)
		_collect_paths(data.get("chains", []), float(data.get("asset_length_m", 12.0)), maps.selected_map, instances)
	_collect_placements(_read_json(CATALOG).get("placements", []), maps.selected_map, instances)
	for scene_path in instances:
		var template := _instantiate(scene_path)
		if template == null:
			push_warning("둔치 보도 에셋 로드 실패: " + scene_path)
			continue
		Batcher.build(self, scene_path.get_file().get_basename(), template, instances[scene_path])
		placed_count += instances[scene_path].size()
		template.free()
	print("RiversideTrialPlacer: ", placed_count, " placed")
	load_complete = true

func _collect_paths(chains: Array, asset_length: float, map, instances: Dictionary) -> void:
	var elevation := Callable(_surface, "height")
	for chain_index in range(chains.size()):
		var chain: Dictionary = chains[chain_index]
		# 생성기가 교차 체인끼리 겹치지 않게 정한 높이 단. 없으면 순번으로 나눈다
		var tier := int(chain.get("tier", chain_index % CHAIN_TIERS))
		var points := PackedVector2Array()
		var inside := true
		for node in chain.nodes:
			inside = inside and _inside(node, map)
			points.append(_world_xz(node, map))
		if not inside or points.size() < 2:
			continue
		var profile := PathProfile.build(points, float(chain.half_width_m), PATH_CLEARANCE_M, elevation)
		var heights: PackedFloat64Array = profile.heights
		var slopes: PackedFloat64Array = profile.slopes
		var scene := str(chain.scene)
		if not instances.has(scene):
			instances[scene] = []
		for k in range(points.size() - 1):
			if points[k].distance_to(points[k + 1]) < 0.5:
				continue
			var lift := CHAIN_TIER_M * float(tier) + ALTERNATE_LIFT_M * float(k % 2)
			var a := Vector3(points[k].x, heights[k] + lift, points[k].y)
			var b := Vector3(points[k + 1].x, heights[k + 1] + lift, points[k + 1].y)
			var slope := (slopes[k] + slopes[k + 1]) * 0.5
			instances[scene].append(PathProfile.segment_transform(a, b, slope, asset_length, SEGMENT_OVERLAP_M))

func _collect_placements(entries: Array, map, instances: Dictionary) -> void:
	for entry in entries:
		if not entry is Dictionary or not _inside(entry.lonlat, map):
			continue
		var xz := _world_xz(entry.lonlat, map)
		var yaw := deg_to_rad(float(entry.get("yaw_degrees", 0.0)))
		var y := float(entry.get("absolute_y_m", 0.0))
		if str(entry.get("ground", "terrain")) == "terrain":
			y = _footprint_max(xz, yaw, entry.get("footprint_half_m", [0.0, 0.0])) + OBJECT_CLEARANCE_M
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(entry.get("scale", 1.0)))
		var scene := str(entry.scene)
		if not instances.has(scene):
			instances[scene] = []
		instances[scene].append(Transform3D(basis, Vector3(xz.x, y + float(entry.get("y_offset_m", 0.0)), xz.y)))

func _footprint_max(xz: Vector2, yaw: float, half: Array) -> float:
	# 회전된 바닥면의 모서리·변 중점·중심 중 가장 높은 지형에 맞춰 묻히지 않게 한다
	var axis_x := Vector2(cos(yaw), -sin(yaw)) * float(half[0])
	var axis_z := Vector2(sin(yaw), cos(yaw)) * float(half[1])
	var best := -INF
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var p: Vector2 = xz + axis_x * sx + axis_z * sz
			best = maxf(best, _surface.height(p.x, p.y))
	return best

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

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
