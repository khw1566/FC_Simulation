extends SceneTree
## 독립 경량 씬을 작은 뷰포트에서만 확인한다.
var viewport: SubViewport
var model: Node3D
var camera: Camera3D
var index := 0
var frames := 0
var entries: Array = []

func _initialize() -> void:
	var all: Array = JSON.parse_string(FileAccess.get_file_as_string("res://metrics.json"))
	var names := ["eonyang_eupseong", "ulsan_waeseong", "ulsan_airport", "RJFF"]
	for name in names:
		for item in all:
			if str(item.path).get_file().get_basename() == name:
				entries.append(item)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 350)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.055, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.0
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 20000.0
	viewport.add_child(camera)
	select.call_deferred()

func select() -> void:
	if model:
		model.queue_free()
	var entry: Dictionary = entries[index]
	model = (load("res://" + str(entry.path)) as PackedScene).instantiate()
	viewport.add_child(model)
	var low: Array = entry.after.aabb_min_m
	var high: Array = entry.after.aabb_max_m
	var bounds := AABB(Vector3(low[0], low[1], low[2]), Vector3(high[0] - low[0], high[1] - low[1], high[2] - low[2]))
	var center := bounds.get_center()
	camera.position = center + Vector3(0.75, 0.65, 1.0).normalized() * maxf(100.0, bounds.size.length() * 2.0)
	camera.look_at(center)
	var projected := AABB()
	for corner in range(8):
		var point := camera.global_transform.affine_inverse() * bounds.get_endpoint(corner)
		projected = AABB(point, Vector3.ZERO) if corner == 0 else projected.expand(point)
	camera.size = maxf(projected.size.y, projected.size.x / (800.0 / 350.0)) * 1.16
	frames = 0

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 16:
		var image := viewport.get_texture().get_image()
		var name: String = str(entries[index].path).get_file().get_basename()
		assert(image.save_png("res://" + name + "_lowpoly.png") == OK)
		index += 1
		if index == entries.size():
			quit()
		else:
			select()
	return false
