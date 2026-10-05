extends Node3D
## 전용 야경 확인 씬. 원본 월드와 분리되어 실행한다.

func _ready() -> void:
	var clock := Node.new()
	clock.set_script(load("res://scripts/services/day_night_cycle_service.gd"))
	clock.name = "DayNightCycleService"
	clock.set("current_time_hours", 22.0)
	clock.set("is_time_progression_active", false)
	add_child(clock)
	var demo = load("res://assets/generated/industrial_plant/plant_assembly_demo.tscn").instantiate()
	add_child(demo)
	var placements := {
		"factory_gable": Vector3(-65, 0, 45),
		"liquid_storage_tank": Vector3(72, 0, 45),
		"lpg_sphere": Vector3(108, 0, 0),
		"cooling_tower": Vector3(80, 0, -55),
		"gantry_crane": Vector3(-15, 0, -105),
		"tower_crane": Vector3(-90, 0, -35),
		"factory_flat": Vector3(0, 0, 110),
	}
	for key in placements:
		var model = load("res://assets/generated/industrial/" + key + ".tscn").instantiate()
		model.position = placements[key]
		add_child(model)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(450, 450)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.075, 0.085, 0.11)
	floor_material.roughness = 0.55
	floor_material.metallic = 0.2
	floor_mesh.material = floor_material
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.05
	add_child(floor_node)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(195, 135, 245)
	camera.fov = 50
	camera.look_at(Vector3(0, 32, 15))
	camera.current = true
	var moon := DirectionalLight3D.new()
	add_child(moon)
	moon.rotation_degrees = Vector3(-48, -35, 0)
	moon.light_color = Color(0.45, 0.58, 0.85)
	moon.light_energy = 0.18
	var env_node := WorldEnvironment.new()
	env_node.environment = Environment.new()
	env_node.environment.background_mode = Environment.BG_COLOR
	env_node.environment.background_color = Color(0.008, 0.014, 0.03)
	env_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_node.environment.ambient_light_color = Color(0.25, 0.32, 0.48)
	env_node.environment.ambient_light_energy = 0.3
	add_child(env_node)
	await get_tree().process_frame
	# 실제 주야간 서비스와 연결해 낮에는 소등, 밤에는 점등됨을 확인한다.
	var rig = demo.get_node("stack_concrete_4/NightLighting")
	clock.call("set_time_hours", 12.0)
	assert(not rig.visible)
	assert(is_zero_approx(rig.get_node("Light0").light_energy))
	clock.call("set_time_hours", 22.0)
	assert(rig.visible)
	assert(rig.get_node("Light0").light_energy > 0.0)
	# 같은 리그 두 인스턴스의 밝기·재질 상태가 독립인지 확인한다.
	var other = load("res://assets/generated/industrial_plant/stack_concrete.tscn").instantiate()
	other.position = Vector3(300, 0, 300)
	add_child(other)
	var other_rig = other.get_node("NightLighting")
	var original_energy: float = rig.get_node("Light0").light_energy
	other_rig.call("set_night_factor", 0.3)
	assert(is_equal_approx(rig.get_node("Light0").light_energy, original_energy))
	assert(other_rig.get_node("Fixture0").material_override != rig.get_node("Fixture0").material_override)
	other.free()
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/industrial_lighting/catalog.json"))
	var count := 0
	for key in catalog.assets:
		assert(load(catalog.assets[key].scene_path) != null)
		count += 1
	print("NIGHT_LIGHTING_OK rigs=", count, " day_off=true night_on=true independent_instances=true")
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../night.png")
	get_tree().quit()
