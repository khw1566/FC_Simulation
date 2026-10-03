extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.1, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1
	world.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 66
	camera.position = Vector3(0, 100, 0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.make_current()
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(64, 64)
	plane.mesh = mesh
	plane.position.y = 10
	world.add_child(plane)
	var mask := Image.create(32, 32, false, Image.FORMAT_L8)
	mask.fill(Color.BLACK)
	for x in range(32):
		var y := roundi(15 + 5 * sin(float(x) * 0.22))
		mask.set_pixel(x, y, Color.WHITE)
	var suffix := ""
	if "--actual-river" in OS.get_cmdline_user_args():
		var source := Image.load_from_file("res://assets/maps/ulsan_metro_80km/hydro/river_mask.png")
		var center := Vector2i(roundi((129.265 - 128.81256666666667) / (129.69843333333336 - 128.81256666666667) * source.get_width()), roundi((35.9049 - 35.585) / (35.9049 - 35.1841) * source.get_height()))
		var nearest := center
		var best := INF
		for y in range(center.y - 80, center.y + 81):
			for x in range(center.x - 80, center.x + 81):
				var distance := Vector2(x, y).distance_squared_to(Vector2(center))
				if source.get_pixel(x, y).r > 0.5 and distance < best:
					best = distance
					nearest = Vector2i(x, y)
		if is_inf(best):
			push_error("실제 하천 검증 구역에 수계가 없습니다.")
			quit(1)
			return
		mask = source.get_region(Rect2i(nearest - Vector2i(48, 48), Vector2i(96, 96)))
		suffix = "_actual"
	mask.generate_mipmaps()
	var texture := ImageTexture.create_from_image(mask)
	for stage in ["before", "after"]:
		var material := ShaderMaterial.new()
		if stage == "before":
			material.shader = Shader.new()
			material.shader.code = FileAccess.get_file_as_string("res://../results/river_shader_before.gdshader")
		else:
			material.shader = load("res://shaders/procedural_terrain.gdshader")
		material.set_shader_parameter("water_mask_texture", texture)
		material.set_shader_parameter("world_size_meters", 64.0)
		material.set_shader_parameter("river_wave_strength", 0.0)
		material.set_shader_parameter("simple_contour_mode", true)
		plane.material_override = material
		for i in range(6):
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var error := image.save_png(ProjectSettings.globalize_path("res://../results/river_filter" + suffix + "_" + stage + ".png"))
		if error != OK:
			quit(1)
			return
	print("하천 1픽셀 곡선 전후 렌더링 완료")
	quit(0)
