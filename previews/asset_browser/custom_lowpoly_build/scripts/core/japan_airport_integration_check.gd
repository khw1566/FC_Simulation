extends SceneTree
const Layout = preload("res://scripts/terrain/regional_airport_layout.gd")
const VectorProjection = preload("res://scripts/terrain/vector_map_projection.gd")
const Classifier = preload("res://scripts/terrain/road_segment_classifier.gd")
var failures: Array[String] = []
var statistics: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _expect(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/japan_airports/placement.json"))
	_expect(catalog.airports.size() == 18, "공항 카탈로그 수")
	for spec in catalog.airports:
		var scene := load(str(spec.scene_path)) as PackedScene
		_expect(scene != null, "공항 씬 로드: " + str(spec.id))
		if scene:
			var model := scene.instantiate()
			_expect(model.find_children("*", "MeshInstance3D", true, false).size() <= 7, "재질 배치 수: " + str(spec.id))
			_expect(model.find_children("*", "StaticBody3D", true, false).size() >= 2, "공항 충돌체: " + str(spec.id))
			model.free()
	var points: Array[Vector3] = [Vector3.ZERO, Vector3(100, 0, 0)]
	var water: Array[float] = [1, 1]
	_expect(Classifier.classify({"bridge": "yes", "structure_tags_verified": true}, points, water)[0] == 1, "OSM 교량 우선")
	_expect(Classifier.classify({"tunnel": "yes", "bridge": "yes"}, points, water)[0] == 2, "터널 우선")
	_expect(Classifier.classify({"bridge": "no", "structure_tags_verified": true}, points, water)[0] == 0, "공유 수계 오판정 차단")
	var loader := root.get_node("LoadingManagerService")
	var service := root.get_node("MapSelectionService")
	for map_id in ["kanmon_straits", "kyushu_wide"]:
		service.select_map_by_id(map_id)
		var started := Time.get_ticks_msec()
		loader.transition_to_map()
		while loader.is_loading and Time.get_ticks_msec() - started < 180000:
			await process_frame
		_expect(not loader.is_loading, "지도 로딩: " + map_id)
		if loader.is_loading:
			loader._return_to_menu()
			continue
		var world := current_scene
		var manager := world.get_node("BuildingRoadManager")
		var airport: Node3D = manager._airport_manager._regional
		_expect(airport._airports.size() == 2, "지도 공항 수: " + map_id)
		var terrain := world.get_node("TerrainManager")
		for entry in airport._airports:
			var center: Vector3 = entry.node.global_position
			var ground_y: float = terrain.get_terrain_elevation(center.x, center.z)
			_expect(absf(ground_y - center.y) < 1.0, "공항 지반 보정: " + str(entry.spec.id) + "/" + map_id)
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/kanmon_straits/map_meta.json"))
		var sample := {"roads": [{"points": [[0.0, 10.0, 0.0]], "width": 8.0}], "buildings": []}
		VectorProjection.apply(sample, meta, service.selected_map)
		var expected_x: float = ((130.95 - service.selected_map.bbox_west) / (service.selected_map.bbox_east - service.selected_map.bbox_west) - 0.5) * service.selected_map.world_size_meters
		_expect(absf(float(sample.roads[0].points[0][0]) - expected_x) < 0.01, "도로 위경도 투영: " + map_id)
		var sea_image := Image.load_from_file(service.selected_map.sea_mask_path)
		var sea_samples := 0
		for gy in range(1, 20):
			for gx in range(1, 20):
				var u := float(gx) / 20
				var v := float(gy) / 20
				var x: float = (u - 0.5) * service.selected_map.world_size_meters
				var z: float = (v - 0.5) * service.selected_map.world_size_meters
				if sea_image.get_pixel(int(u * (sea_image.get_width()-1)), int(v * (sea_image.get_height()-1))).r > 0.99 and not airport.replaces_building(x, z):
					sea_samples += 1
					_expect(terrain.get_terrain_elevation(x, z) < 0, "해수 지형 수면 아래: %s/%s" % [map_id, Vector2(gx, gy)])
		_expect(sea_samples > 50, "해수 검증 표본 수")
		_expect(service.selected_map.world_size_meters == 28000 and service.selected_map.max_elevation == 750, "원본 DEM 범위·고도 해석")
		var raw := JSON.parse_string(FileAccess.get_file_as_string(service.selected_map.buildings_roads_path)) as Dictionary
		var original_center: Array = raw.buildings[0].center.duplicate()
		VectorProjection.apply(raw, meta, service.selected_map)
		_expect(raw.buildings[0].center == original_center, "건물 원본 좌표 보존")
		var player := world.get_node("Player")
		player.process_mode = Node.PROCESS_MODE_DISABLED
		var chosen: Dictionary = airport._airports.filter(func(e): return e.spec.id == "RJFR")[0]
		var center: Vector3 = chosen.node.global_position
		var camera := player.get_node("Camera3D") as Camera3D
		camera.global_position = center + Vector3(2200, 2400, 1800)
		camera.look_at(center, Vector3.UP)
		await create_timer(3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../results/261003_%s_airports.png" % map_id)
		statistics[map_id] = {"airports": airport._airports.size(), "load_seconds": (Time.get_ticks_msec() - started) / 1000.0, "fps": Engine.get_frames_per_second()}
		loader._return_to_menu()
		for i in range(8):
			await process_frame
	var output := FileAccess.open("res://../results/261003_japan_airport_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "maps": statistics}, "  "))
	print(JSON.stringify({"failures": failures, "maps": statistics}))
	quit(0 if failures.is_empty() else 1)


