extends SceneTree
## 새 칸몬 건물의 지역 이동 스트리밍과 경사지·중정 메시를 실제 GPU로 확인한다.
const Builder = preload("res://scripts/terrain/building_mesh_builder.gd")
var failures: Array[String] = []
var regions: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func run() -> void:
	if "--hud-only" in OS.get_cmdline_user_args():
		root.get_node("MapSelectionService").select_map_by_id("kanmon_straits")
		var hud = load("res://scenes/map_hud.tscn").instantiate()
		root.add_child(hud)
		await process_frame
		hud.toggle_fullscreen_map()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../results/261003_kanmon_building_attribution.png")
		print("칸몬 건물 자료 출처 HUD 확인")
		quit()
		return
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fixture := Node3D.new()
	root.add_child(fixture)
	Builder.build_chunk_buildings_mesh([{"polygon": [[0,0],[10,0],[10,10],[0,10]], "center": [5,0,5], "height": 3, "height_source": "osm_height", "base_y": 0}], fixture, material, func(x,_z,_fallback): return x)
	var mesh := fixture.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var roof := -INF
	for point in vertices:
		roof = maxf(roof, point.y)
	expect(absf(roof - 13.0) < .01, "경사지 최대 지반 + 실제 높이 3m 보존")
	fixture.queue_free()
	var service := root.get_node("MapSelectionService")
	service.select_map_by_id("kanmon_straits")
	var loader := root.get_node("LoadingManagerService")
	var start := Time.get_ticks_msec()
	loader.transition_to_map()
	while loader.is_loading and Time.get_ticks_msec() - start < 240000:
		await process_frame
	expect(not loader.is_loading, "칸몬 맵 로딩")
	if loader.is_loading:
		finish()
		return
	var world := current_scene
	var host := world.get_node("BuildingRoadManager")
	expect(host.load_error.is_empty(), "스트리밍 오류 없음")
	var stream: Node = host.get_children().filter(func(node): return node.get_script() == preload("res://scripts/terrain/vector_data_stream.gd"))[0]
	var count := 0
	for entry in stream.entries:
		if entry.kind == "buildings":
			count += int(entry.count)
	expect(count == 321584, "전체 외곽선 인덱스 수")
	var player := world.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var meta = service.selected_map
	for region in [{"id":"kokura","lat":33.886,"lon":130.88},{"id":"mojiko","lat":33.945,"lon":130.96},{"id":"shimonoseki","lat":33.956,"lon":130.938},{"id":"north_shimonoseki","lat":34.01,"lon":130.955}]:
		var point := Vector2(((region.lon-meta.bbox_west)/(meta.bbox_east-meta.bbox_west)-.5)*meta.world_size_meters, ((meta.bbox_north-region.lat)/(meta.bbox_north-meta.bbox_south)-.5)*meta.world_size_meters)
		var terrain := world.get_node("TerrainManager")
		var y: float = terrain.get_terrain_elevation(point.x, point.y)
		player.global_position = Vector3(point.x,y+650,point.y)
		await create_timer(8).timeout
		var camera := player.get_node("Camera3D") as Camera3D
		camera.global_position = Vector3(point.x+500,y+600,point.y+700)
		camera.look_at(Vector3(point.x,y,point.y),Vector3.UP)
		host._last_cull_check_pos = Vector3.INF
		host._update_chunk_culling()
		await create_timer(3).timeout
		var near := 0
		for record in stream.loaded.values():
			if Vector2(record.entry.center[0],record.entry.center[1]).distance_to(point) < 3000:
				near += int(record.entry.count)
		expect(near > 500, "지역 건물 생성: " + region.id)
		expect(stream.error.is_empty(), "지역 자료 오류: " + region.id)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../results/261003_kanmon_buildings_%s.png" % region.id)
		regions[region.id] = {"nearby_source_buildings": near,"resident_buildings":stream.resident_buildings,"fps":Engine.get_frames_per_second(),"loaded_building_batches":stream.loaded.size()}
	finish()

func finish() -> void:
	var result := {"passed":failures.is_empty(),"failures":failures,"regions":regions}
	var file := FileAccess.open("res://../results/261003_kanmon_building_render_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

