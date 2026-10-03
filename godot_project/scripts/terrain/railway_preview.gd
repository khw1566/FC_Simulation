extends SceneTree

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.14, 0.17, 0.21)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.83, 0.9)
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-25,0)
	light.light_energy = 1.2
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(1400,800)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.22,0.24,0.21)
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = -0.25
	world.add_child(floor_mesh)
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/railway/services.json"))
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(100, 165, 290)
	camera.look_at(Vector3(-40, 0, -30))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 480
	camera.far = 2000
	camera.current = true
	for index in settings.services.size():
		var profile: Dictionary = settings.services[index]
		var z: float = 25.0 if index == 0 else -45.0
		var points := PackedVector3Array([Vector3(-600,0,z), Vector3(600,0,z)])
		var track := preload("res://scripts/terrain/railway_track_builder.gd").build(points, profile, {"bridge":false}, 10000)
		world.add_child(track)
		var train := preload("res://scripts/terrain/railway_train_builder.gd").build(profile)
		world.add_child(train)
		var travelled := 0.0
		for car_index in train.get_child_count():
			var car := train.get_child(car_index) as Node3D
			var length: float = float(profile.car_length_m)
			if profile.id == "ktx" and (car_index == 0 or car_index == train.get_child_count()-1):
				length = float(profile.power_car_length_m)
			car.position = Vector3(140 - travelled - length * 0.5, 0.12, z)
			travelled += length + float(profile.car_gap_m)
			car.rotation.y = -PI/2.0
		var label := Label3D.new()
		label.text = "동해선 4량 전동차 / 자갈 도상" if index == 0 else "KTX 20량 편성 / 콘크리트 도상"
		label.font_size = 64
		label.pixel_size = 0.07
		label.position = Vector3(-30, 14, z - 15)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png("res://../results/261004_railway_preview.png")
	for index in settings.services.size():
		var z: float = 25.0 if index == 0 else -45.0
		camera.position = Vector3(165, 18, z + 50)
		camera.look_at(Vector3(95,2,z))
		camera.size = 55
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://../results/261004_railway_%s.png" % settings.services[index].id)
	print("[철도 미리보기] 별도 경량 모델 렌더링 완료")
	quit()
