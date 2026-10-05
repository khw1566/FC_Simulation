extends SceneTree

const Manager = preload("res://scripts/terrain/industrial_zone_manager.gd")
const Preferences = preload("res://scripts/services/user_settings_service.gd")
const Controller = preload("res://scripts/controllers/pause_settings_controller.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var directory: String = get_script().resource_path.get_base_dir()
	var terrain = load(directory.path_join("industrial_runtime_terrain.gd")).new()
	root.add_child(terrain)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Manager.CATALOG))
	var viewer := Node3D.new()
	root.add_child(viewer)
	var manager := Manager.new()
	manager.auto_initialize = false
	manager.terrain_manager = terrain
	manager.player_node = viewer
	root.add_child(manager)
	var preferences := Preferences.new()
	preferences.settings_file_path = directory.path_join("industrial_runtime_settings.cfg")
	var zone: Dictionary = data.zones[0]
	viewer.position = Vector3(zone.center_xz[0],50,zone.center_xz[1])
	manager.configure(data,preferences)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12,0.14,0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	root.add_child(light)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1550
	camera.far = 5000
	camera.current = true
	root.size = Vector2i(1280,960)
	var counts: Array = []
	for spec in data.zones:
		viewer.position = Vector3(spec.center_xz[0],50,spec.center_xz[1])
		manager._update_visibility()
		for frame in 120:
			manager._process(1.0/60)
			if manager._queue.is_empty():
				break
			await process_frame
		if manager._models.size()!=int(spec.asset_count):
			failures.append("구역 %d 상세 모델 수 불일치" % spec.zone_id)
		counts.append(manager._models.size())
		camera.position = Vector3(spec.center_xz[0]+1050,1250,spec.center_xz[1]+850)
		camera.look_at(Vector3(spec.center_xz[0],20,spec.center_xz[1]))
		var slab := MeshInstance3D.new()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for z in 64:
			for x in 64:
				for offset in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
					var px: float = spec.center_xz[0]-750+(x+offset.x)*1500/64.0
					var pz: float = spec.center_xz[1]-750+(z+offset.y)*1500/64.0
					surface.add_vertex(Vector3(px,terrain.get_terrain_elevation(px,pz),pz))
		surface.generate_normals()
		slab.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.30,0.32,0.30)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		slab.material_override = material
		root.add_child(slab)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("261004_IndustrialZone_%d.png" % spec.zone_id))
		slab.free()
	var view = load("res://scenes/pause_settings_hud.tscn").instantiate()
	viewer.position += Vector3(4000,0,0)
	manager._update_visibility()
	if not manager._models.is_empty():
		failures.append("원거리에서 상세 모델 미해제")
	root.add_child(view)
	var controller := Controller.new()
	controller.pause_view = view
	controller.user_settings_service = preferences
	controller._connect_view_signals()
	view.industrial_zones_check.button_pressed = false
	if manager.enabled or not manager._models.is_empty() or manager._content.visible:
		failures.append("설정 끄기 실패")
	var restored := Preferences.new()
	restored.settings_file_path = preferences.settings_file_path
	restored.load_settings()
	if restored.industrial_zones_enabled:
		failures.append("공단 설정 저장 실패")
	view.industrial_zones_check.button_pressed = true
	if not manager.enabled or not manager._content.visible:
		failures.append("설정 재활성화 실패")
	view.show_settings_menu()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("261004_IndustrialSettings.png"))
	var report := {"near_models_per_zone":counts,"total_assets":data.placements.size(),"failures":failures}
	var file := FileAccess.open(directory.path_join("261004_IndustrialRuntimeValidation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	controller.free()
	preferences.free()
	restored.free()
	view.free()
	manager.free()
	viewer.free()
	terrain.free()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
