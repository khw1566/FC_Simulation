extends SceneTree
const Clouds = preload("res://scripts/weather/procedural_cloud_manager.gd")
const Builder = preload("res://scripts/terrain/building_mesh_builder.gd")
const Policy = preload("res://scripts/terrain/building_shadow_policy.gd")
const Weather = preload("res://preview_weather.gd")
const Cycle = preload("res://preview_cycle.gd")
var _records: Dictionary = {}
var _world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _fixture(x: float, z: float, height: float = 9.0) -> Dictionary:
	return {"center": [x, 0.0, z], "size": [8.0, height, 8.0], "height": height,
		"height_source": "fixture", "polygon": [[x-4,z-4],[x+4,z-4],[x+4,z+4],[x-4,z+4]]}

func _check_buildings() -> void:
	var buildings: Array = []
	for x in 3:
		for z in 3:
			buildings.append(_fixture(float(x) * 10.0 - 10.0, float(z) * 10.0 - 10.0))
	buildings[8].erase("polygon")
	buildings.append(_fixture(200, 200))
	buildings.append(_fixture(5, 5, 30.0))
	var campus := _fixture(10, 10)
	campus["_campus_art_candidate"] = true
	buildings.append(campus)
	var groups := Policy.split(buildings)
	assert(groups.dense.size() == 9)
	assert(groups.regular.size() == 3)
	var ground := func(_x, _z, _fallback): return 0.0
	var result := Builder.compute_arrays(buildings, ground)
	assert(result.shadow_skipped_buildings == 9)
	var original := Builder._compute_geometry(buildings, ground)
	assert(_vertices(original, ["major", "minor"]) == _vertices(result, ["major", "minor", "dense_major", "dense_minor"]))
	var node := Node3D.new()
	_world.add_child(node)
	Builder.apply_arrays(result, node, StandardMaterial3D.new(), ground)
	var disabled := 0
	var enabled := 0
	for container in node.get_children():
		for mesh in container.get_children():
			if mesh is MeshInstance3D:
				if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					disabled += 1
				else:
					enabled += 1
	assert(disabled > 0 and enabled > 0)
	_records.buildings = {"dense_disabled": 9, "isolated_tall_campus_preserved": 3,
		"shadow_disabled_meshes": disabled, "shadow_enabled_meshes": enabled,
		"polygon_box_negative_grid_boundary": true, "geometry_and_collision_faces_preserved": true}

func _vertices(result: Dictionary, keys: Array) -> Dictionary:
	var counts: Dictionary = {}
	for key in keys:
		for arrays in result.get(key, []):
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				counts[vertex] = int(counts.get(vertex, 0)) + 1
	return counts

func _capture(label: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://images/" + label + ".png")

func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_check_buildings()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.51, 0.72)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.68, 0.8)
	environment.environment.ambient_light_energy = 0.65
	environment.environment.fog_enabled = true
	environment.environment.fog_density = 0.00006
	environment.environment.fog_light_color = Color(0.6, 0.7, 0.8)
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20, 162, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500
	_world.add_child(sun)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(0, 180, 450)
	camera.look_at(Vector3(0, 850, -2500))
	camera.far = 30000
	camera.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12000, 12000)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.46, 0.38)
	ground.material_override = material
	_world.add_child(ground)
	var cycle := Cycle.new()
	_world.add_child(cycle)
	var weather := Weather.new()
	weather.sun_light = sun
	weather.world_environment = environment
	weather.day_night_service = cycle
	_world.add_child(weather)
	var cloud := Clouds.new()
	cloud.player_node = camera
	cloud.day_night_service = cycle
	cloud.transition_seconds = 0.1
	weather.add_child(cloud)
	cloud.configure_composition(0.85, 0.2, 0.3, 0.0, Color(0.96,0.97,1), Color(0.6,0.65,0.73), Color(0.3,0.32,0.38))
	var optics := cloud.get_node("OpticalEffects")
	if DisplayServer.get_name() == "headless":
		for i in 8:
			await process_frame
	else:
		DirAccess.make_dir_recursive_absolute("res://images")
		for i in 40:
			await process_frame
		cloud.set_process(false)
		optics.cloud_shadows_enabled = false
		optics.light_rays_enabled = false
		optics.lens_flare_enabled = false
		await _capture("baseline")
		optics.cloud_shadows_enabled = true
		optics.light_rays_enabled = true
		optics.lens_flare_enabled = true
		await _capture("optics")
		optics.cloud_shadows_enabled = false
		optics.lens_flare_enabled = false
		await _capture("rays_only")
		cloud._ratios = Vector4.ZERO
		cloud._apply_composition()
		cloud._layer.visible = false
		optics.light_rays_enabled = false
		await _capture("clear_baseline")
		optics.lens_flare_enabled = true
		await _capture("clear_flare")
		_records.flare_state = {"visible": optics._light.visible,
			"sun_uv": str(optics._light_material.get_shader_parameter("sun_uv")),
			"visibility": optics._light_material.get_shader_parameter("flare_visibility"),
			"compatibility": optics._light_material.get_shader_parameter("compatibility_depth"),
			"clouds_active": optics._light_material.get_shader_parameter("clouds_active")}
		# 태양 픽셀을 불투명 메시로 가렸을 때 플레어가 사라지는 비교.
		var blocker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(130, 130, 30)
		blocker.mesh = box
		_world.add_child(blocker)
		blocker.position = camera.position + sun.global_basis.z * 600.0
		await _capture("occluded")
		optics.lens_flare_enabled = false
		await _capture("occluded_baseline")
		blocker.queue_free()
	# 설정과 야간 차단은 장면 전체를 실행하지 않고 직접 확인한다.
	sun.shadow_enabled = false
	await process_frame
	await process_frame
	assert(not optics._shadow.visible)
	environment.environment.fog_enabled = false
	cloud._sync_environment()
	await process_frame
	assert(float(optics._light_material.get_shader_parameter("haze_density")) == 0.0)
	cycle.current_time_hours = 23.0
	await process_frame
	assert(not optics._light.visible)
	_records.settings_and_night = true
	_records.full_world_run = false
	_records.renderer = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open("res://verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_records, "  "))
	file.close()
	print("OPTICS_CHECK_OK ", JSON.stringify(_records))
	quit()
