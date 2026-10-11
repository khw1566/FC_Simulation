extends Node3D
class_name BuildingRoadManager

const BuildingMeshBuilder = preload("res://scripts/terrain/building_mesh_builder.gd")
var _campus_ground_loaded := false
const AirportManager = preload("res://scripts/terrain/airport_landmark_manager.gd")
const RoadClassifier = preload("res://scripts/terrain/road_segment_classifier.gd")
const RoadBatchBuilder = preload("res://scripts/terrain/road_batch_builder.gd")
const BridgeManager = preload("res://scripts/terrain/bridge_landmark_manager.gd")
const HeritageManager = preload("res://scripts/terrain/heritage_landmark_manager.gd")
const DamManager = preload("res://scripts/terrain/dam_landmark_manager.gd")
const CivilManager = preload("res://scripts/terrain/taehwa_civil_manager.gd")
const RailwayManager = preload("res://scripts/terrain/railway_world_manager.gd")

var _heritage_manager: Node3D
var _railway_manager: Node3D
const VectorStream = preload("res://scripts/terrain/vector_data_stream.gd")
const Quality = preload("res://scripts/models/render_quality_profile.gd")
var initial_load_radius := 2000.0
var prefetch_distance := 500.0
var load_complete := false
var load_error := ""
var load_status := "지형 준비 대기"
var load_progress := 0.0
var _road_metadata: Dictionary = {}
var _road_metadata_loaded := false
var _batch_serial := 0
var _seen_road_geometry: Dictionary = {}

var _bridge_manager: Node3D

var _airport_manager: Node3D

@export var buildings_roads_path: String = "res://assets/generated/buildings_and_roads.json"
@export var terrain_manager: Node3D
@export var player_node: Node3D

# 건물 기초 지형 매립 깊이 (경사지/절개지 건물이 공중에 뜨지 않도록 하부 연장 스커트)
@export var foundation_depth: float = 12.0

# 건물 공간 분할 및 거리 기반 컬링/LOD 설정
@export var chunk_size: float = 1500.0
@export var max_view_distance: float = 7500.0
@export var small_building_cutoff_distance: float = 3000.0 # 원거리 소형 건물 조기 생략

var _building_chunk_nodes: Dictionary = {}
var _last_cull_check_pos: Vector3 = Vector3(99999, 99999, 99999)
var _cull_timer: float = 0.0
var _max_cull_altitude: float = 12000.0
var _high_cull_altitude: float = 8000.0
const CULL_HYSTERESIS := 400.0
const BatchAssembler = preload("res://scripts/terrain/building_batch_assembler.gd")
var _collision_stream := preload("res://scripts/terrain/building_collision_stream.gd").new()
var _industrial_suppression := preload("res://scripts/terrain/industrial_building_suppression.gd").new()

# 박스 빌딩, 일반 도로, 터널 아치 튜브, 교량 구조물 재질
var building_material: StandardMaterial3D
var road_material: Material
var walking_path_material: Material
var unpaved_road_material: Material
var tunnel_wall_material: StandardMaterial3D
var bridge_truss_material: StandardMaterial3D
var bridge_tower_material: StandardMaterial3D
var bridge_cable_material: StandardMaterial3D

# 터널 세그먼트 공간 인덱스 캐시 (플레이어 터널 통과 판정용)
var tunnel_segments: Array[Dictionary] = []

func _ready() -> void:
	_initialize_async.call_deferred()

func _exit_tree() -> void:
	_collision_stream.dispose()

func _initialize_async() -> void:
	while is_instance_valid(terrain_manager) and not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			load_error = terrain_manager.load_error
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_init_from_map_selection()
	_init_materials()
	_load_airport_landmark()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_load_bridge_landmarks()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_load_heritage_landmarks()
	_load_dam_landmarks()
	_load_taehwa_civil()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await _load_railways()
	await load_and_render_all()

func _load_railways() -> void:
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null or service.selected_map.id != "ulsan_metro_80km":
		return
	load_status = "울산 철도 및 운행 열차 구성"
	var manager := RailwayManager.new()
	_railway_manager = manager
	manager.name = "UlsanRailways"
	add_child(manager)
	await manager.setup(service.selected_map, terrain_manager, player_node)
	if not manager.load_error.is_empty():
		push_warning(manager.load_error)

func _load_dam_landmarks() -> void:
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null:
		return
	var manager := DamManager.new()
	manager.name = "UlsanDams"
	add_child(manager)
	manager.setup(service.selected_map, terrain_manager)

func _load_taehwa_civil() -> void:
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null:
		return
	var manager := CivilManager.new()
	manager.name = "TaehwaCivilFacilities"
	add_child(manager)
	manager.setup(service.selected_map)

func _load_heritage_landmarks() -> void:
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null:
		return
	_heritage_manager = HeritageManager.new()
	_heritage_manager.name = "UlsanHeritageLandmarks"
	add_child(_heritage_manager)
	_heritage_manager.setup(service.selected_map, terrain_manager)

func _load_bridge_landmarks() -> void:
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null:
		return
	_bridge_manager = BridgeManager.new()
	_bridge_manager.name = "TaehwaBridges"
	add_child(_bridge_manager)
	_bridge_manager.setup(service.selected_map, terrain_manager)

func _load_airport_landmark() -> void:
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null:
		return
	var map_config = service.selected_map
	_industrial_suppression.configure(str(map_config.id))
	if map_config.airport_placement_path.is_empty():
		return
	_airport_manager = AirportManager.new()
	_airport_manager.name = "AirportLandmark"
	add_child(_airport_manager)
	_airport_manager.setup(map_config.airport_placement_path, map_config, terrain_manager)

func _init_from_map_selection() -> void:
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			if not svc.selected_map.buildings_roads_path.is_empty():
				buildings_roads_path = svc.selected_map.buildings_roads_path
			var w_size: float = svc.selected_map.world_size_meters
			max_view_distance = 25000.0 if w_size >= 100000.0 else (8000.0 if w_size >= 40000.0 else 4500.0)
			small_building_cutoff_distance = 9000.0 if w_size >= 100000.0 else (3500.0 if w_size >= 40000.0 else 2200.0)
			_max_cull_altitude = 22000.0 if w_size >= 100000.0 else 12000.0
			_high_cull_altitude = 12000.0 if w_size >= 100000.0 else 8000.0
	var quality := Quality.current()
	max_view_distance = minf(max_view_distance, float(quality.view_distance))
	small_building_cutoff_distance = minf(small_building_cutoff_distance, float(quality.minor_distance))
	initial_load_radius = minf(max_view_distance, float(quality.initial_radius))
	prefetch_distance = float(quality.prefetch)
	var default_map_path := "res://assets/maps/kanmon_straits/buildings_and_roads.json"
	if not FileAccess.file_exists(buildings_roads_path) and FileAccess.file_exists(default_map_path):
		buildings_roads_path = default_map_path

func _init_materials() -> void:
	building_material = StandardMaterial3D.new()
	building_material.albedo_color = Color(0.82, 0.84, 0.86, 1.0)
	building_material.roughness = 0.85
	building_material.metallic_specular = 0.15
	building_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	building_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

	var fallback_road := StandardMaterial3D.new()
	fallback_road.albedo_color = Color(0.18, 0.19, 0.20, 1.0)
	fallback_road.roughness = 0.95
	fallback_road.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_material = fallback_road
	if terrain_manager and terrain_manager.has_method("create_road_material"):
		var conformed: Material = terrain_manager.call("create_road_material")
		if conformed != null:
			road_material = conformed
	walking_path_material = _make_road_variant(Color(0.29, 0.28, 0.25), 0.24)
	unpaved_road_material = _make_road_variant(Color(0.34, 0.31, 0.25), 0.32)

	tunnel_wall_material = StandardMaterial3D.new()
	tunnel_wall_material.albedo_color = Color(0.40, 0.42, 0.44, 1.0)
	tunnel_wall_material.roughness = 0.8
	tunnel_wall_material.metallic_specular = 0.2
	tunnel_wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tunnel_wall_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

	bridge_truss_material = StandardMaterial3D.new()
	bridge_truss_material.albedo_color = Color(0.68, 0.70, 0.72, 1.0)
	bridge_truss_material.roughness = 0.5
	bridge_truss_material.metallic = 0.6
	bridge_truss_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bridge_truss_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

	bridge_tower_material = StandardMaterial3D.new()
	bridge_tower_material.albedo_color = Color(0.85, 0.87, 0.90, 1.0)
	bridge_tower_material.roughness = 0.4
	bridge_tower_material.metallic = 0.7
	bridge_tower_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bridge_tower_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

	bridge_cable_material = StandardMaterial3D.new()
	bridge_cable_material.albedo_color = Color(0.25, 0.26, 0.28, 1.0)
	bridge_cable_material.roughness = 0.4
	bridge_cable_material.metallic = 0.8
	bridge_cable_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bridge_cable_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

func _make_road_variant(color: Color, clearance: float) -> Material:
	if road_material is ShaderMaterial:
		var variant := (road_material as ShaderMaterial).duplicate() as ShaderMaterial
		variant.set_shader_parameter("road_color", Vector3(color.r, color.g, color.b))
		variant.set_shader_parameter("clearance", clearance)
		return variant
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = color
	fallback.roughness = 1.0
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	return fallback

func load_and_render_all() -> void:
	if not FileAccess.file_exists(buildings_roads_path):
		load_error = "지도 건물 파일이 없습니다."
		return
	var stream := VectorStream.new()
	add_child(stream)
	await stream.run(self, buildings_roads_path)
	if not is_inside_tree():
		return
	load_error = stream.error
	load_complete = load_error.is_empty()

## 도로 메타데이터를 처음 요청할 때 읽는다. 메인 스레드에서 호출한다.
func road_metadata_entries() -> Dictionary:
	if not _road_metadata_loaded:
		_road_metadata_loaded = true
		var path := buildings_roads_path.get_base_dir().path_join("road_metadata.json")
		if FileAccess.file_exists(path):
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				_road_metadata = data.get("entries", {})
	return _road_metadata

func _apply_road_metadata(roads: Array) -> void:
	RoadBatchBuilder.apply_metadata(roads, road_metadata_entries())

func _process(delta: float) -> void:
	_cull_timer += delta
	if _cull_timer < 0.05:
		return
	_cull_timer = 0.0
	_update_chunk_culling()
	if player_node:
		var ppos := player_node.global_position
		# 지면에서 충분히 높이 날 때는 건물 충돌체를 새로 만들지 않는다.
		var clearance := ppos.y - _sample_ground_height(ppos.x, ppos.z, 0.0)
		_collision_stream.update(_building_chunk_nodes, Vector2(ppos.x, ppos.z), clearance)

func _update_chunk_culling() -> void:
	if not player_node:
		var parent = get_parent()
		if parent:
			player_node = parent.get_node_or_null("Player") as Node3D
	if not player_node:
		return

	var ppos: Vector3 = player_node.global_position
	if ppos.distance_squared_to(_last_cull_check_pos) < 400.0:
		return
	_last_cull_check_pos = ppos

	var player_alt := ppos.y
	var p_pos_2d := Vector2(ppos.x, ppos.z)

	# 1. 초고고도: 픽셀 단위로도 식별 불가하므로 건물 전체 일괄 컬링 (지형에 GPU 100% 집중)
	if player_alt >= _max_cull_altitude:
		for chunk_info in _building_chunk_nodes.values():
			var chunk_node: Node3D = chunk_info.get("node")
			if chunk_node and chunk_node.visible:
				chunk_node.visible = false
		return

	var is_high_alt := (player_alt >= _high_cull_altitude)
	for chunk_info in _building_chunk_nodes.values():
		_apply_chunk_visibility(chunk_info, p_pos_2d, is_high_alt)

## 경계에서 켜짐/꺼짐이 반복되지 않도록 표시 기준보다 넓은 여유 거리를 지나야 숨긴다.
## chunk_info: {"node": Node3D, "center_2d": Vector2, "minor": Node3D}
func _apply_chunk_visibility(chunk_info: Dictionary, p_pos_2d: Vector2, is_high_alt: bool) -> void:
	var chunk_node: Node3D = chunk_info.get("node")
	if chunk_node == null:
		return
	var dist := p_pos_2d.distance_to(chunk_info.get("center_2d", Vector2.ZERO))
	var show_chunk := dist <= max_view_distance or (chunk_node.visible and dist <= max_view_distance + CULL_HYSTERESIS)
	if chunk_node.visible != show_chunk:
		chunk_node.visible = show_chunk
	if not show_chunk:
		return
	# 대형/소형 계층적 가시성 제어: 고고도이거나 원경에서는 소형 건물 생략
	var minor_node: Node3D = chunk_info.get("minor")
	if minor_node:
		var near_minor := dist <= small_building_cutoff_distance or (minor_node.visible and dist <= small_building_cutoff_distance + CULL_HYSTERESIS)
		var show_minor: bool = (not is_high_alt) and near_minor
		if minor_node.visible != show_minor:
			minor_node.visible = show_minor

func _render_buildings_batched(buildings: Array) -> Node3D:
	if buildings.is_empty():
		return null
	var chunks := BatchAssembler.group(self, buildings)
	return BatchAssembler.attach(self, BatchAssembler.compute(chunks, _sample_ground_height))

## 작업 스레드용 지형 높이 샘플러. 장면 트리를 조회하지 않는다.
func threaded_ground_sampler() -> Callable:
	var terrain := terrain_manager
	return func(x: float, z: float, fallback: float) -> float:
		if terrain == null:
			return fallback
		var elevation: float = terrain.get_terrain_elevation(x, z)
		return elevation if elevation > -90.0 else fallback

## 작업 스레드용 수계 마스크 샘플러. 장면 트리를 조회하지 않는다.
func threaded_water_sampler() -> Callable:
	var terrain := terrain_manager
	return func(x: float, z: float) -> float:
		if terrain == null or not terrain.has_method("get_water_mask"):
			return 0.0
		return float(terrain.get_water_mask(x, z))

func release_building_batch(container: Node3D) -> void:
	if not is_instance_valid(container):
		return
	for key in _building_chunk_nodes.keys():
		if _building_chunk_nodes[key].node.get_parent() == container:
			_building_chunk_nodes.erase(key)
	container.queue_free()

## 도로 배치를 만든다. threaded가 참이면 메시 계산을 작업 스레드에서 수행하고 프레임을 넘기며 기다린다.
## 반환값의 signatures·batch는 release_road_batch()에서 중복 판정과 터널 구간을 되돌릴 때 사용한다.
func _render_roads_and_tunnels_batched(roads: Array, threaded: bool = false, batch: String = "") -> Dictionary:
	var accepted: Array = []
	var signatures: Array = []
	var pieces: Array = []
	for r in roads:
		if _bridge_manager != null and _bridge_manager.replaces_road(r):
			continue
		pieces.append_array(_bridge_manager.clip_road(r) if _bridge_manager != null else [r])
	for r in pieces:
		var signature: String = r["_geometry_key"] if r.has("_geometry_key") else RoadClassifier.geometry_key(r)
		if _seen_road_geometry.has(signature):
			continue
		_seen_road_geometry[signature] = true
		signatures.append(signature)
		accepted.append(r)
	var record := {"container": null, "signatures": signatures, "batch": batch}
	if accepted.is_empty():
		return record
	var terrain_step := Vector2.ZERO
	var terrain_origin := Vector2.ZERO
	if terrain_manager and road_material is ShaderMaterial:
		var size: float = terrain_manager.terrain_world_size
		terrain_step = Vector2(size / float(terrain_manager.grid_chunks_x) / terrain_manager.base_resolution, size / float(terrain_manager.grid_chunks_y) / terrain_manager.base_resolution)
		terrain_origin = Vector2.ONE * -size * 0.5
	var ground := threaded_ground_sampler()
	var water := threaded_water_sampler()
	var formed_ground: bool = terrain_manager != null and terrain_manager._road_grader.enabled
	var result: Dictionary
	if threaded:
		var holder := [null]
		var task := WorkerThreadPool.add_task(func(): holder[0] = RoadBatchBuilder.compute(accepted, ground, water, terrain_step, terrain_origin, formed_ground), false, "도로 배치 준비")
		while not WorkerThreadPool.is_task_completed(task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		result = holder[0]
	else:
		result = RoadBatchBuilder.compute(accepted, ground, water, terrain_step, terrain_origin, formed_ground)
	if not is_inside_tree():
		return record
	for segment in result.tunnel_segments:
		segment["batch"] = batch
		tunnel_segments.append(segment)
	record.container = RoadBatchBuilder.attach(self, result)
	return record

## 멀어진 도로 배치를 해제하고 중복 판정 키와 터널 구간을 되돌린다.
func release_road_batch(record: Dictionary) -> void:
	for signature in record.get("signatures", []):
		_seen_road_geometry.erase(signature)
	var batch: String = record.get("batch", "")
	if not batch.is_empty():
		tunnel_segments.assign(tunnel_segments.filter(func(segment): return segment.get("batch", "") != batch))
	var container = record.get("container")
	if is_instance_valid(container):
		container.queue_free()

func _configure_road_bounds(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mesh_instance.get_meta("formed_ground", false):
		return
	if terrain_manager == null or not road_material is ShaderMaterial:
		return
	var bounds := mesh_instance.mesh.get_aabb()
	bounds.position.y = float(terrain_manager.min_elevation) - 4
	bounds.size.y = float(terrain_manager.max_elevation) - bounds.position.y + 4
	mesh_instance.custom_aabb = bounds

func is_point_in_tunnel(pos: Vector3) -> bool:
	for seg in tunnel_segments:
		var s: Vector3 = seg["start"]
		var e: Vector3 = seg["end"]
		var rad: float = seg["radius"]

		var seg_vec := e - s
		var l2 := seg_vec.length_squared()
		if l2 == 0.0:
			continue
		var t := clampf((pos - s).dot(seg_vec) / l2, 0.0, 1.0)
		var proj := s + t * seg_vec
		if pos.distance_to(proj) <= rad:
			return true
	return false

## 지형 매니저로부터 해당 좌표의 실제 지반 고도를 쿼리하거나 기본 높이를 반환
func _sample_ground_height(wx: float, wz: float, fallback_h: float) -> float:
	if not terrain_manager:
		var parent = get_parent()
		if parent:
			terrain_manager = parent.get_node_or_null("TerrainManager") as Node3D

	if terrain_manager and terrain_manager.has_method("get_terrain_elevation"):
		var elev: float = float(terrain_manager.call("get_terrain_elevation", wx, wz))
		if elev > -90.0:
			return elev
	return fallback_h

## 지형 매니저로부터 해당 좌표의 수계 마스크 강도(0.0~1.0)를 쿼리
func _sample_water_mask(wx: float, wz: float) -> float:
	if not terrain_manager:
		var parent = get_parent()
		if parent:
			terrain_manager = parent.get_node_or_null("TerrainManager") as Node3D

	if terrain_manager and terrain_manager.has_method("get_water_mask"):
		return float(terrain_manager.call("get_water_mask", wx, wz))
	return 0.0

## 방파제 데이터를 별도 BreakwaterLighthouseRenderer 노드에 위임 렌더링
func _render_breakwaters(breakwaters: Array) -> void:
	if breakwaters.is_empty():
		return
	var RendererClass = load("res://scripts/terrain/breakwater_lighthouse_renderer.gd")
	if not RendererClass:
		return
	var renderer = RendererClass.new()
	renderer.name = "BreakwaterRenderer"
	renderer.terrain_manager = terrain_manager
	add_child(renderer)
	renderer.render_breakwaters(breakwaters)
