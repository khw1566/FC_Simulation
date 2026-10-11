extends Node3D
class_name TerrainChunkManager

const TerrainChunkClass = preload("res://scripts/terrain/terrain_chunk.gd")
const CoastlineWaterCarver = preload("res://scripts/terrain/coastline_water_carver.gd")
const AirfieldGrader = preload("res://scripts/terrain/airfield_terrain_grader.gd")
const MapImages = preload("res://scripts/services/map_image_preloader.gd")
const Quality = preload("res://scripts/models/render_quality_profile.gd")
var base_resolution := 128
const LOD_HYSTERESIS := 600.0
var startup_timings: Dictionary = {}
var _height_texture: ImageTexture
var _water_sdf_texture: ImageTexture = null
var _river_bed_applied := false

var airport_floor_y: float = NAN
var _airport_placement_path: String = ""
var _airport_map_meta: Dictionary = {}
var _road_lod_image: Image
var _road_lod_texture: ImageTexture
var _coastal_corrected: bool = false
var _railway_grader: RefCounted
var _road_grader := preload("res://scripts/terrain/road_formation_grader.gd").new()
var _sea_mask_path: String = ""
var _lake_mask_path: String = ""

@export var player_node: Node3D
@export var min_elevation: float = -50.0
@export var max_elevation: float = 750.0
@export var terrain_world_size: float = 28000.0 # 28km
@export var grid_chunks_x: int = 4
@export var grid_chunks_y: int = 4

# 청크 거리별 LOD 기준값 (미터) - 해안선 및 항만 조망 거리 확장
@export var lod0_distance: float = 7000.0
@export var lod1_distance: float = 14000.0
@export var lod2_distance: float = 28000.0

var heightmap_override_path: String = ""
var watermask_override_path: String = ""
var splatmap_override_path: String = ""
var buildings_roads_override_path: String = ""

var active_chunks: Dictionary = {}
var terrain_material: Material
var _full_heightmap_image: Image
var _full_watermask_image: Image
var is_simple_contour_mode: bool = false
var load_complete := false
var load_error := ""
var load_status := "지형 자료 읽기"

func toggle_terrain_render_mode() -> bool:
	is_simple_contour_mode = !is_simple_contour_mode
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("simple_contour_mode", is_simple_contour_mode)
	print("[TerrainChunkManager] Terrain Render Style: ", "등고선 심플 모드" if is_simple_contour_mode else "위성 정밀 피복 모드")
	return is_simple_contour_mode

func _ready() -> void:
	_initialize_async.call_deferred()

func _initialize_async() -> void:
	_init_from_map_selection()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_init_shader_material()
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_load_heightmap()
	if _full_heightmap_image == null or _full_heightmap_image.is_empty():
		load_error = "지도 높이맵을 읽지 못했습니다."
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var chunks_started := Time.get_ticks_msec()
	await _build_all_chunks()
	startup_timings["chunks_ms"] = Time.get_ticks_msec() - chunks_started
	if not is_inside_tree():
		return
	_build_subsurface_bed()
	if _river_bed_applied:
		var water := preload("res://scripts/water/taehwa_water_manager.gd").new()
		water.name = "TaehwaFlowingWater"
		add_child(water)
		await water.setup("ulsan_metro_80km", terrain_material as ShaderMaterial)
	load_complete = true

func _init_from_map_selection() -> void:
	base_resolution = int(Quality.current().base_resolution)
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			var m = svc.selected_map
			_coastal_corrected = m.coastal_heightmap_corrected
			_sea_mask_path = m.sea_mask_path
			_lake_mask_path = m.lake_mask_path
			min_elevation = m.min_elevation
			max_elevation = m.max_elevation
			terrain_world_size = m.world_size_meters
			heightmap_override_path = m.heightmap_path
			watermask_override_path = m.watermask_path
			splatmap_override_path = m.splatmap_path
			buildings_roads_override_path = m.buildings_roads_path
			_airport_placement_path = m.airport_placement_path
			_airport_map_meta = {"world_size_meters": m.world_size_meters, "bbox": {"south": m.bbox_south, "north": m.bbox_north, "west": m.bbox_west, "east": m.bbox_east}}

			# 맵 크기별 청크 그리드 및 LOD 거리 동적 적응 (광역맵 버텍스 밀도 및 공간 분해능 극대화)
			if terrain_world_size >= 100000.0: # 140km 동남권 메가리전
				grid_chunks_x = 8
				grid_chunks_y = 8
				lod0_distance = 18000.0
				lod1_distance = 45000.0
				lod2_distance = 90000.0
			elif terrain_world_size >= 80000.0: # 80km에서도 기존 청크당 공간 해상도 유지
				grid_chunks_x = 11
				grid_chunks_y = 11
				lod0_distance = 12000.0
				lod1_distance = 28000.0
				lod2_distance = 75000.0
			elif terrain_world_size >= 40000.0: # 60km 울산 광역권
				grid_chunks_x = 8
				grid_chunks_y = 8
				lod0_distance = 12000.0
				lod1_distance = 28000.0
				lod2_distance = 55000.0
			else: # 5km 울산대 캠퍼스 등 로컬 맵
				grid_chunks_x = 4
				grid_chunks_y = 4
				lod0_distance = 7000.0
				lod1_distance = 14000.0
				lod2_distance = 28000.0

			print("[TerrainChunkManager] Applied MapConfig: %s | WorldSize: %.0fm | Grid: %dx%d" % [m.id, terrain_world_size, grid_chunks_x, grid_chunks_y])
	var quality := Quality.current()
	# 건물 표시 범위 안의 지형은 상세 LOD를 유지해 건물·철도와 지면이 어긋나 보이지 않게 한다.
	if quality.id == "light":
		lod0_distance = minf(lod0_distance, 6500.0)
		lod1_distance = minf(lod1_distance, 14000.0)
	elif quality.id == "standard":
		lod0_distance = minf(lod0_distance, 8500.0)
		lod1_distance = minf(lod1_distance, 20000.0)

func _build_subsurface_bed() -> void:
	# 맵 전체의 지하 하부에 영구 물리 지지판(Subsurface Bed) 배치
	var bed_body := StaticBody3D.new()
	bed_body.name = "SubsurfaceBed"
	bed_body.collision_layer = 1
	bed_body.collision_mask = 1

	var bed_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(terrain_world_size + 4000.0, 10.0, terrain_world_size + 4000.0)
	bed_shape.shape = box
	bed_shape.position = Vector3(0.0, min_elevation - 25.0, 0.0)

	bed_body.add_child(bed_shape)
	add_child(bed_body)
	print("[TerrainChunkManager] Created Subsurface Bed at Y=%.1f (thickness 10m)." % [min_elevation - 20.0])

func _init_shader_material() -> void:
	var shader = load("res://shaders/procedural_terrain.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("min_height", min_elevation)
		mat.set_shader_parameter("max_height", max_elevation)
		mat.set_shader_parameter("world_size_meters", terrain_world_size)
		for binding in [[_sea_mask_path, "sea_mask_texture", "has_sea_mask"], [_lake_mask_path, "lake_mask_texture", "has_lake_mask"]]:
			if not binding[0].is_empty() and FileAccess.file_exists(binding[0]):
				var image := MapImages.read(binding[0])
				if image != null:
					mat.set_shader_parameter(binding[1], ImageTexture.create_from_image(image))
					mat.set_shader_parameter(binding[2], true)

		# 등고선 간격: 광역(28km)은 25m, 정밀 구역(3km)은 5m~10m로 자연스러운 스케일 조정
		var auto_contour_interval: float = 10.0 if terrain_world_size <= 5000.0 else 25.0
		mat.set_shader_parameter("contour_interval", auto_contour_interval)

		# 수계 마스크 (하천 및 호수 절차적 수면 셰이딩)
		var mask_path := watermask_override_path
		if mask_path.is_empty() or not FileAccess.file_exists(mask_path):
			mask_path = "res://assets/maps/kanmon_straits/kanmon_watermask_8bit.png"
		if not FileAccess.file_exists(mask_path):
			mask_path = "res://assets/generated/kanmon_watermask_8bit.png"

		if FileAccess.file_exists(mask_path):
			var mask_img := MapImages.read(mask_path)
			if mask_img:
				_full_watermask_image = mask_img
				# 물리·지형 절삭은 원본을 유지하고 렌더링 복사본에만 밉맵을 만든다.
				var render_mask := mask_img.duplicate() as Image
				render_mask.generate_mipmaps()
				var mask_tex := ImageTexture.create_from_image(render_mask)
				mat.set_shader_parameter("water_mask_texture", mask_tex)
				print("[TerrainChunkManager] Loaded water mask texture: ", mask_path)
			# 렌더링 전용 수계 거리장: 마스크 해상도보다 좁은 하천의 픽셀화·끊김을 막는다.
			var sdf_path := mask_path.get_base_dir().path_join("water_sdf.png")
			if FileAccess.file_exists(sdf_path):
				var sdf_img := MapImages.read(sdf_path)
				if sdf_img:
					_water_sdf_texture = ImageTexture.create_from_image(sdf_img)
					mat.set_shader_parameter("water_sdf_texture", _water_sdf_texture)
					mat.set_shader_parameter("has_water_sdf", true)

		# 4채널 지표 피복 스플랫맵 (산림, 농경지/논밭, 도회지, 하천/수계)
		var splat_path := splatmap_override_path
		if splat_path.is_empty() and heightmap_override_path.is_empty():
			splat_path = "res://assets/maps/kanmon_straits/kanmon_splatmap_rgba.png"
		if not FileAccess.file_exists(splat_path) and heightmap_override_path.is_empty():
			splat_path = "res://assets/generated/kanmon_splatmap_rgba.png"

		if FileAccess.file_exists(splat_path):
			var splat_img := MapImages.read(splat_path)
			if splat_img:
				var splat_tex := ImageTexture.create_from_image(splat_img)
				mat.set_shader_parameter("splatmap_texture", splat_tex)
				mat.set_shader_parameter("has_splatmap", true)
				print("[TerrainChunkManager] Loaded splatmap texture: ", splat_path)

		terrain_material = mat

func _load_heightmap() -> void:
	var height_started := Time.get_ticks_msec()
	var raw_path := heightmap_override_path
	_road_grader.configure(buildings_roads_override_path)
	if raw_path.is_empty() or not FileAccess.file_exists(raw_path):
		raw_path = "res://assets/maps/kanmon_straits/kanmon_heightmap_16bit.png"
	if not FileAccess.file_exists(raw_path):
		raw_path = "res://assets/generated/kanmon_heightmap_16bit.png"

	if raw_path.contains("ulsan_metro_80km") and FileAccess.file_exists("res://assets/generated/railway/graded_heightmap_16bit.png"):
		raw_path = "res://assets/generated/railway/graded_heightmap_16bit.png"
		var selection := get_node_or_null("/root/MapSelectionService")
		if selection and selection.selected_map:
			raw_path = Quality.heightmap_path(selection.selected_map)
		_railway_grader = preload("res://scripts/terrain/railway_terrain_grader.gd").new()
		var alignment := preload("res://scripts/terrain/railway_alignment_catalog.gd").new()
		_railway_grader.configure(alignment.data)
		_railway_grader.edge_limit = float(Quality.current().rail_edge)
		preload("res://scripts/terrain/railway_terrain_void.gd").configure_bounds(alignment.data)
	if FileAccess.file_exists(raw_path):
		_full_heightmap_image = MapImages.read(raw_path).duplicate()
		_full_heightmap_image.convert(Image.FORMAT_RF)
		if _railway_grader != null and terrain_material is ShaderMaterial:
			var void_image := preload("res://scripts/terrain/railway_terrain_void.gd").image()
			if void_image:
				terrain_material.set_shader_parameter("railway_tunnel_void_texture",ImageTexture.create_from_image(void_image))
				terrain_material.set_shader_parameter("has_railway_tunnel_void",true)
		if not _coastal_corrected:
			CoastlineWaterCarver.apply_coastline_carving(_full_heightmap_image, _full_watermask_image, min_elevation, max_elevation)
		if not _coastal_corrected and not _sea_mask_path.is_empty():
			preload("res://scripts/terrain/sea_terrain_corrector.gd").apply(_full_heightmap_image, MapImages.read(_sea_mask_path), min_elevation, max_elevation)
		if not _airport_placement_path.is_empty() and FileAccess.file_exists(_airport_placement_path):
			var airport_spec = JSON.parse_string(FileAccess.get_file_as_string(_airport_placement_path))
			if airport_spec is Dictionary and airport_spec.has("airfield"):
					airport_floor_y = AirfieldGrader.apply(_full_heightmap_image, airport_spec, _airport_map_meta, min_elevation, max_elevation)
			elif airport_spec is Dictionary and airport_spec.has("airports"):
				preload("res://scripts/terrain/regional_airport_grader.gd").apply(_full_heightmap_image, airport_spec, _airport_map_meta, min_elevation, max_elevation)
		var river_selection := get_node_or_null("/root/MapSelectionService")
		if river_selection and river_selection.selected_map:
			_river_bed_applied = preload("res://scripts/water/river_bed_grade.gd").apply(
				_full_heightmap_image, str(river_selection.selected_map.id), min_elevation, max_elevation, terrain_material as ShaderMaterial)
		if terrain_material is ShaderMaterial and _full_watermask_image != null:
			_height_texture = ImageTexture.create_from_image(_full_heightmap_image)
			terrain_material.set_shader_parameter("coast_height_texture", _height_texture)
			terrain_material.set_shader_parameter("has_coast_height", true)
			get_tree().call_group("sea_water_plane", "set_water_source", _height_texture,
				terrain_material.get_shader_parameter("water_mask_texture"), min_elevation, max_elevation, terrain_material, _water_sdf_texture)
		print("[TerrainChunkManager] Successfully loaded and carved heightmap: ", raw_path)
		startup_timings["height_prepare_ms"] = Time.get_ticks_msec() - height_started
	else:
		push_error("[TerrainChunkManager] Heightmap not found at: " + raw_path)

func _build_all_chunks() -> void:
	if not _full_heightmap_image:
		return

	var chunk_size_x := terrain_world_size / float(grid_chunks_x)
	var chunk_size_y := terrain_world_size / float(grid_chunks_y)
	var half_world := terrain_world_size * 0.5

	var img_w := _full_heightmap_image.get_width()
	var img_h := _full_heightmap_image.get_height()
	var tile_img_w := img_w / grid_chunks_x
	var tile_img_h := img_h / grid_chunks_y

	for cy in range(grid_chunks_y):
		for cx in range(grid_chunks_x):
			var coord := Vector2i(cx, cy)
			
			# 청크 간 경계선 틈새(Seam/Crack) 방지를 위해 1픽셀 오버랩(Overlap) 적용
			var px0: int = cx * tile_img_w
			var py0: int = cy * tile_img_h
			var px1: int = mini((cx + 1) * tile_img_w + 1, img_w)
			var py1: int = mini((cy + 1) * tile_img_h + 1, img_h)
			var rect := Rect2i(px0, py0, px1 - px0, py1 - py0)
			var sub_img := _full_heightmap_image.get_region(rect)

			var center_x := (float(cx) + 0.5) * chunk_size_x - half_world
			var center_z := (float(cy) + 0.5) * chunk_size_y - half_world
			var center_pos := Vector3(center_x, 0.0, center_z)

			var chunk_node := TerrainChunkClass.new()
			chunk_node.name = "Chunk_%d_%d" % [cx, cy]
			chunk_node.init_chunk(coord, chunk_size_x, center_pos, sub_img, min_elevation, max_elevation)
			chunk_node.road_grader = _road_grader if _road_grader.enabled else null
			chunk_node.railway_grader = _railway_grader
			chunk_node.base_resolution = base_resolution
			add_child(chunk_node)
			
			active_chunks[coord] = chunk_node
			load_status = "지형 구역 준비 %d / %d" % [active_chunks.size(), grid_chunks_x * grid_chunks_y]
			await get_tree().process_frame
			if not is_inside_tree():
				return

	print("[TerrainChunkManager] Initialized %d chunk tiles (%dx%d grid)" % [active_chunks.size(), grid_chunks_x, grid_chunks_y])
	_update_chunks_lod()
	await _wait_for_lod_builds()

func _physics_process(_delta: float) -> void:
	if not load_complete:
		return
	if Engine.get_physics_frames() % 15 == 0:
		_update_chunks_lod()
	# 작업 스레드에서 끝난 LOD 메시는 프레임당 하나씩 적용해 생성 순간의 끊김을 막는다.
	_apply_finished_builds(1)

## 지도 시작 시 첫 LOD 메시가 모두 준비될 때까지 기다린다.
func _wait_for_lod_builds() -> void:
	# 화면이 꺼진 로딩 중에는 코어를 더 써서 첫 메시를 빨리 만든다.
	TerrainChunkClass.max_concurrent_builds = maxi(1, OS.get_processor_count() - 2)
	while is_inside_tree():
		_apply_finished_builds(active_chunks.size())
		var remaining := _update_chunks_lod()
		if remaining == 0:
			break
		load_status = "지형 상세도 준비: 남은 구역 %d" % remaining
		await get_tree().process_frame
	TerrainChunkClass.max_concurrent_builds = 1

func _apply_finished_builds(limit: int) -> void:
	var applied := 0
	for chunk in active_chunks.values():
		if applied >= limit:
			break
		if chunk.is_building() and chunk.poll_build(terrain_material):
			applied += 1
	if applied > 0:
		_sync_road_lods()

## LOD 목표를 정하고 메시 계산을 요청한다. 계산은 작업 스레드에서 진행된다.
## 아직 목표 LOD에 도달하지 않은 청크 수를 반환한다.
func _update_chunks_lod() -> int:
	if not player_node:
		return 0
	var remaining := 0
	var player_pos := player_node.global_position
	var lod_changed: bool = false
	# 계산 자리가 하나뿐이므로 가까운 청크부터 요청한다.
	var order: Array = active_chunks.values()
	order.sort_custom(func(a, b): return a.chunk_center.distance_squared_to(player_pos) < b.chunk_center.distance_squared_to(player_pos))

	for chunk in order:
		var dist: float = chunk.chunk_center.distance_to(player_pos)

		# 경계 왕복 시 메쉬가 반복 교체되지 않도록 상세 LOD는 여유 거리만큼 더 유지한다.
		var target_lod: int = 2
		if dist <= lod0_distance or (chunk.current_lod == 0 and dist <= lod0_distance + LOD_HYSTERESIS):
			target_lod = 0
		elif dist <= lod1_distance or (chunk.current_lod == 1 and dist <= lod1_distance + LOD_HYSTERESIS):
			target_lod = 1

		if chunk.current_lod != target_lod:
			chunk.update_lod(target_lod, terrain_material)
			# 캐시된 LOD는 즉시 바뀌므로 도로 LOD도 함께 맞춘다.
			lod_changed = lod_changed or chunk.current_lod == target_lod
			if chunk.current_lod != target_lod:
				remaining += 1
	if lod_changed:
		_sync_road_lods()
	return remaining

func create_road_material() -> Material:
	if _full_heightmap_image == null:
		return null
	if _road_lod_image == null:
		_road_lod_image = Image.create(grid_chunks_x, grid_chunks_y, false, Image.FORMAT_RF)
		_road_lod_texture = ImageTexture.create_from_image(_road_lod_image)
	_sync_road_lods()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/road_surface.gdshader")
	if _height_texture == null:
		_height_texture = ImageTexture.create_from_image(_full_heightmap_image)
	material.set_shader_parameter("road_heightmap", _height_texture)
	material.set_shader_parameter("terrain_base_resolution", float(base_resolution))
	material.set_shader_parameter("terrain_lods", _road_lod_texture)
	material.set_shader_parameter("chunk_counts", Vector2(grid_chunks_x, grid_chunks_y))
	material.set_shader_parameter("world_size", terrain_world_size)
	material.set_shader_parameter("min_elevation", min_elevation)
	material.set_shader_parameter("max_elevation", max_elevation)
	return material

func _sync_road_lods() -> void:
	if _road_lod_image == null:
		return
	_road_lod_image.fill(Color(2, 0, 0))
	for coord in active_chunks:
		_road_lod_image.set_pixel(coord.x, coord.y, Color(clampi(active_chunks[coord].current_lod, 0, 2), 0, 0))
	_road_lod_texture.update(_road_lod_image)

## 특정 월드 좌표(world_x, world_z)에서의 지형 표고(Y)를 높이맵 이미지로부터 바이리니어 보간 샘플링
func get_terrain_elevation(world_x: float, world_z: float) -> float:
	var height := CoastlineWaterCarver.sample_elevation_bilinear(_full_heightmap_image, world_x, world_z, terrain_world_size, min_elevation, max_elevation)
	height = _road_grader.corrected_height(Vector3(world_x,height,world_z))
	return _railway_grader.corrected_height(Vector3(world_x,height,world_z)) if _railway_grader else height

func get_navigation_floor(point: Vector3) -> float:
	var floor: float = preload("res://scripts/terrain/railway_terrain_void.gd").floor_at(point)
	return floor if is_finite(floor) else get_terrain_elevation(point.x,point.z)

func get_rendered_terrain_elevation(world_x: float,world_z: float) -> float:
	var uv := Vector2(world_x,world_z)/terrain_world_size+Vector2(0.5,0.5)
	var coord := Vector2i(clampi(floori(uv.x*grid_chunks_x),0,grid_chunks_x-1),clampi(floori(uv.y*grid_chunks_y),0,grid_chunks_y-1))
	return active_chunks[coord].get_surface_height(world_x,world_z) if active_chunks.has(coord) else get_terrain_elevation(world_x,world_z)

## 특정 월드 좌표(world_x, world_z)에서의 수계 마스크 강도(0.0: 완전 육지, 1.0: 수면/하천)를 샘플링
func get_water_mask(world_x: float, world_z: float) -> float:
	if not _full_watermask_image:
		return 0.0

	var half_size: float = terrain_world_size * 0.5
	var u: float = (world_x + half_size) / terrain_world_size
	var v: float = (world_z + half_size) / terrain_world_size

	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return 0.0

	var img_w: int = _full_watermask_image.get_width()
	var img_h: int = _full_watermask_image.get_height()

	var px: int = int(clampf(u * float(img_w - 1), 0.0, float(img_w - 1)))
	var py: int = int(clampf(v * float(img_h - 1), 0.0, float(img_h - 1)))

	return _full_watermask_image.get_pixel(px, py).r
