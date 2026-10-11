extends Node3D
class_name BuildingRoadManager

const BuildingMeshBuilder = preload("res://scripts/terrain/building_mesh_builder.gd")
const CampusGround = preload("res://scripts/terrain/campus_ground_overlay.gd")
var _campus_ground_loaded := false
const RoadMeshBuilder = preload("res://scripts/terrain/road_mesh_builder.gd")
const AirportManager = preload("res://scripts/terrain/airport_landmark_manager.gd")
const RoadClassifier = preload("res://scripts/terrain/road_segment_classifier.gd")
const BridgeManager = preload("res://scripts/terrain/bridge_landmark_manager.gd")
const HeritageManager = preload("res://scripts/terrain/heritage_landmark_manager.gd")
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
var _collision_stream := preload("res://scripts/terrain/building_collision_stream.gd").new()

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

func _apply_road_metadata(roads: Array) -> void:
	var path := buildings_roads_path.get_base_dir().path_join("road_metadata.json")
	if not FileAccess.file_exists(path):
		return
	if not _road_metadata_loaded:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			return
		_road_metadata = data.get("entries", {})
		_road_metadata_loaded = true
	var entries: Dictionary = _road_metadata
	for road in roads:
		var metadata: Dictionary = entries.get(str(road.get("id", "")), {})
		if metadata.get("points_sha256", "") != JSON.stringify(road.get("points", [])).sha256_text():
			continue
		road["width"] = float(metadata.width)
		road["layer"] = metadata.layer
		road["osm_id"] = metadata.osm_id
		for key in ["bridge", "tunnel", "surface", "structure_tags_verified"]:
			if metadata.has(key):
				road[key] = metadata[key]

func _process(delta: float) -> void:
	_cull_timer += delta
	if _cull_timer < 0.05:
		return
	_cull_timer = 0.0
	_update_chunk_culling()
	if player_node:
		_collision_stream.update(_building_chunk_nodes, Vector2(player_node.global_position.x, player_node.global_position.z))

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
		for coord in _building_chunk_nodes.keys():
			var chunk_info: Dictionary = _building_chunk_nodes[coord]
			var chunk_node: Node3D = chunk_info.get("node")
			if chunk_node and chunk_node.visible:
				chunk_node.visible = false
		return

	var is_high_alt := (player_alt >= _high_cull_altitude)
	for coord in _building_chunk_nodes.keys():
		var chunk_info: Dictionary = _building_chunk_nodes[coord]
		var chunk_node: Node3D = chunk_info.get("node")
		if chunk_node:
			_apply_chunk_visibility(chunk_node, chunk_info.get("center_2d", Vector2.ZERO), p_pos_2d, is_high_alt)

## 경계에서 켜짐/꺼짐이 반복되지 않도록 표시 기준보다 넓은 여유 거리를 지나야 숨긴다.
func _apply_chunk_visibility(chunk_node: Node3D, center_pos: Vector2, p_pos_2d: Vector2, is_high_alt: bool) -> void:
	var dist := p_pos_2d.distance_to(center_pos)
	var show_chunk := dist <= max_view_distance or (chunk_node.visible and dist <= max_view_distance + CULL_HYSTERESIS)
	if chunk_node.visible != show_chunk:
		chunk_node.visible = show_chunk
	if not show_chunk:
		return
	# 대형/소형 계층적 가시성 제어: 고고도이거나 원경에서는 소형 건물 생략
	var minor_node := chunk_node.get_node_or_null("MinorBuildings") as Node3D
	if minor_node:
		var near_minor := dist <= small_building_cutoff_distance or (minor_node.visible and dist <= small_building_cutoff_distance + CULL_HYSTERESIS)
		var show_minor: bool = (not is_high_alt) and near_minor
		if minor_node.visible != show_minor:
			minor_node.visible = show_minor

func _render_buildings_batched(buildings: Array) -> Node3D:
	if buildings_roads_path.contains("ulsan_uc_west"):
		preload("res://scripts/terrain/campus_building_policy.gd").mark_imagery_candidates(buildings)
	if not _campus_ground_loaded and buildings_roads_path.contains("ulsan_uc_west"):
		var campus_step := 5000.0 / 512.0
		CampusGround.build(self, _sample_ground_height, campus_step, -2500.0)
		_campus_ground_loaded = true
	if buildings.is_empty():
		return null

	var bldg_container := Node3D.new()
	bldg_container.name = "BuildingsContainer"
	add_child(bldg_container)

	# 1. 1,500m 단위 공간 청크별로 건물 분류
	var chunks_data: Dictionary = {}
	for b in buildings:
		# 수집 자료의 0 높이는 미지정 값일 수 있다. 실제 기초 높이는
		# BuildingMeshBuilder에서 현재 지형을 샘플링하여 결정한다.

		var center_arr: Array = b.get("center", [0, 0, 0])
		var cx: float = float(center_arr[0])
		var cz: float = float(center_arr[2])

		var poly_arr: Array = b.get("polygon", [])
		if poly_arr.size() >= 3:
			cx = 0.0
			cz = 0.0
			for p in poly_arr:
				if p is Array and p.size() >= 2:
					cx += float(p[0])
					cz += float(p[1])
			cx /= float(poly_arr.size())
			cz /= float(poly_arr.size())

		if _airport_manager != null and _airport_manager.replaces_building(cx, cz):
			continue
		if _heritage_manager != null and _heritage_manager.replaces_building(cx, cz, str(b.get("name", ""))):
			continue
		if _railway_manager != null and _railway_manager.landmarks != null and _railway_manager.landmarks.replaces_building(cx,cz):
			continue
		var coord := Vector2i(int(floor(cx / chunk_size)), int(floor(cz / chunk_size)))
		if not chunks_data.has(coord):
			chunks_data[coord] = []
		chunks_data[coord].append(b)

	_batch_serial += 1

	# 2. 공간 청크별 메시 배치 생성
	for coord in chunks_data.keys():
		var chunk_buildings: Array = chunks_data[coord]
		var chunk_node := Node3D.new()
		chunk_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
		bldg_container.add_child(chunk_node)

		var chunk_center := Vector2((float(coord.x) + 0.5) * chunk_size, (float(coord.y) + 0.5) * chunk_size)
		_building_chunk_nodes[Vector3i(coord.x, coord.y, _batch_serial)] = {"node": chunk_node, "center_2d": chunk_center}
		BuildingMeshBuilder.build_chunk_buildings_mesh(chunk_buildings, chunk_node, building_material, _sample_ground_height)
		# 생성 직후 한 프레임이라도 원거리 블록이 보였다가 사라지는 깜박임을 막는다.
		if player_node:
			chunk_node.visible = false
			_apply_chunk_visibility(chunk_node, chunk_center, Vector2(player_node.global_position.x, player_node.global_position.z), player_node.global_position.y >= _high_cull_altitude)
	_last_cull_check_pos = Vector3.INF
	return bldg_container

func release_building_batch(container: Node3D) -> void:
	if not is_instance_valid(container):
		return
	for key in _building_chunk_nodes.keys():
		if _building_chunk_nodes[key].node.get_parent() == container:
			_building_chunk_nodes.erase(key)
	container.queue_free()

func _render_roads_and_tunnels_batched(roads: Array, yield_budget: Callable = Callable()) -> void:
	if roads.is_empty():
		return

	var road_container := Node3D.new()
	road_container.name = "RoadsContainer"
	add_child(road_container)

	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walking_st := SurfaceTool.new()
	walking_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var unpaved_st := SurfaceTool.new()
	unpaved_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tunnel_st := SurfaceTool.new()
	tunnel_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bridge_st := SurfaceTool.new()
	bridge_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var road_count: int = 0
	var walking_count: int = 0
	var unpaved_count: int = 0
	var tunnel_count: int = 0
	var bridge_count: int = 0
	var terrain_step := Vector2.ZERO
	var terrain_origin := Vector2.ZERO
	if terrain_manager and road_material is ShaderMaterial:
		var size: float = terrain_manager.terrain_world_size
		terrain_step = Vector2(size / float(terrain_manager.grid_chunks_x) / terrain_manager.base_resolution, size / float(terrain_manager.grid_chunks_y) / terrain_manager.base_resolution)
		terrain_origin = Vector2.ONE * -size * 0.5

	var seen_roads: Dictionary = _seen_road_geometry
	for r in roads:
		if not is_inside_tree():
			return
		if yield_budget.is_valid():
			await yield_budget.call()
		else:
			await get_tree().process_frame
		if not is_inside_tree():
			return
		if _bridge_manager != null and _bridge_manager.replaces_road(r):
			continue
		var signature := RoadClassifier.geometry_key(r)
		if seen_roads.has(signature):
			continue
		seen_roads[signature] = true
		var raw_pts: Array = r.get("points", [])
		if raw_pts.size() < 2:
			continue

		var width: float = float(r.get("width", 8.0))

		# 1단계: 도로 선분을 곡률 적응형으로 세분화 (RoadMeshBuilder에 위임)
		var sub_pts: Array[Vector3] = RoadMeshBuilder.subdivide_polyline(raw_pts)
		if sub_pts.size() < 2:
			continue

		# 2단계: 실제 지형 고도 및 수계 마스크 샘플링
		var ground_y_list: Array[float] = []
		var water_mask_list: Array[float] = []
		for p in sub_pts:
			var gy: float = _sample_ground_height(p.x, p.z, p.y)
			var wm: float = _sample_water_mask(p.x, p.z)
			ground_y_list.append(gy)
			water_mask_list.append(wm)

		var segment_types := RoadClassifier.classify(r, sub_pts, water_mask_list)
		var first: int = 0
		while first < segment_types.size():
			var kind: int = segment_types[first]
			var last: int = first + 1
			while last < segment_types.size() and segment_types[last] == kind:
				last += 1
			var section: Array[Vector3] = []
			var section_ground: Array[float] = []
			for index in range(first, last + 1):
				section.append(sub_pts[index])
				section_ground.append(ground_y_list[index])
			if kind == 0:
				var road_type := str(r.get("type", ""))
				if road_type in ["footway", "path", "steps", "pedestrian", "bridleway", "corridor"]:
					RoadMeshBuilder.build_surface_road(walking_st, section, section_ground, width, _sample_ground_height, terrain_step, terrain_origin, 0.24)
					walking_count += 1
				elif road_type in ["track", "cycleway"]:
					RoadMeshBuilder.build_surface_road(unpaved_st, section, section_ground, width, _sample_ground_height, terrain_step, terrain_origin, 0.32)
					unpaved_count += 1
				else:
					RoadMeshBuilder.build_surface_road(road_st, section, section_ground, width, _sample_ground_height, terrain_step, terrain_origin)
					road_count += 1
			elif kind == 1:
				RoadMeshBuilder.build_universal_bridge(bridge_st, section, section_ground, width)
				bridge_count += 1
			else:
				# 광역 수집 데이터의 Y=0은 실측 터널 고도가 아니라 미지정 값이다.
				if str(r.get("id", "")).begins_with("rd_metro_") or r.get("projected_source", false):
					var cumulative: Array[float] = [0.0]
					for index in range(1, section.size()):
						cumulative.append(cumulative[-1] + section[index].distance_to(section[index - 1]))
					for index in range(section.size()):
						section[index].y = lerpf(section_ground[0], section_ground[-1], cumulative[index] / maxf(0.01, cumulative[-1])) + 0.2
				RoadMeshBuilder.build_mountain_tunnel(tunnel_st, section, width, tunnel_segments)
				tunnel_count += 1
			first = last
		# 배치 분할 커밋
		if road_count + walking_count + unpaved_count >= 1500:
			_commit_road_surface(road_container, road_st, road_material, "PavedRoads", road_count)
			_commit_road_surface(road_container, walking_st, walking_path_material, "WalkingPaths", walking_count)
			_commit_road_surface(road_container, unpaved_st, unpaved_road_material, "UnpavedAndCycleways", unpaved_count)
			road_st = SurfaceTool.new(); road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
			walking_st = SurfaceTool.new(); walking_st.begin(Mesh.PRIMITIVE_TRIANGLES)
			unpaved_st = SurfaceTool.new(); unpaved_st.begin(Mesh.PRIMITIVE_TRIANGLES)
			road_count = 0
			walking_count = 0
			unpaved_count = 0

	_commit_road_surface(road_container, road_st, road_material, "PavedRoads", road_count)
	_commit_road_surface(road_container, walking_st, walking_path_material, "WalkingPaths", walking_count)
	_commit_road_surface(road_container, unpaved_st, unpaved_road_material, "UnpavedAndCycleways", unpaved_count)

	if tunnel_count > 0:
		var m = tunnel_st.commit()
		var mi = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = tunnel_wall_material
		road_container.add_child(mi)

	if bridge_count > 0:
		var m = bridge_st.commit()
		var mi = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = bridge_truss_material
		road_container.add_child(mi)
		preload("res://scripts/terrain/structure_collision.gd").add_trimesh(mi)

func _commit_road_surface(container: Node3D, surface: SurfaceTool, material: Material, node_name: String, road_sections: int) -> void:
	if road_sections <= 0:
		return
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	_configure_road_bounds(instance)
	container.add_child(instance)

func _configure_road_bounds(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

