extends Node3D

const Manager = preload("res://scripts/terrain/heritage_landmark_manager.gd")
const Terrain = preload("res://scripts/terrain/terrain_chunk_manager.gd")
const MapConfig = preload("res://scripts/models/map_config_model.gd")
var camera: Camera3D
var manager: Node3D
var terrain: Node3D
var label: Label
var target := Vector3.ZERO
var distance := 390.0
var yaw := 0.3
var pitch := 0.65

func _ready() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/ulsan_metro_80km/map_meta.json"))
	var config = MapConfig.create_from_dict(meta)
	terrain = Terrain.new()
	terrain.terrain_world_size = config.world_size_meters
	terrain.min_elevation = config.min_elevation
	terrain.max_elevation = config.max_elevation
	terrain._full_heightmap_image = Image.load_from_file(config.heightmap_path)
	terrain._full_heightmap_image.convert(Image.FORMAT_RF)
	manager = Manager.new()
	add_child(manager)
	manager.setup(config, terrain)
	for placement in manager.placements:
		_ground(placement.model)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.16, 0.20, 0.24)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.8, 0.86, 0.94)
	settings.ambient_light_energy = 0.45
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1200
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 48
	camera.near = 0.3
	camera.far = 4000
	add_child(camera)
	camera.make_current()
	var ui := CanvasLayer.new()
	label = Label.new()
	label.position = Vector2(25, 24)
	label.add_theme_font_size_override("font_size", 23)
	ui.add_child(label)
	add_child(ui)
	_show(0)
	if "--capture-heritage" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _ground(model: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := 600.0
	var steps := 80
	for z in range(steps):
		for x in range(steps):
			for offset in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var p := Vector3((x + offset.x) * span / steps - span / 2, 0, (z + offset.y) * span / steps - span / 2)
				p = model.to_global(p)
				p.y = terrain.get_terrain_elevation(p.x, p.z) - 0.05
				surface.add_vertex(p)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.32, 0.22)
	mat.roughness = 1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	add_child(instance)

func _show(index: int) -> void:
	var placement: Dictionary = manager.placements[0 if index == 0 else 1]
	var local := Vector3(0, 0, 0)
	if index == 2:
		local = Vector3(placement.spec.gate.x, 0, placement.spec.gate.z)
	target = placement.model.to_global(local)
	target.y = terrain.get_terrain_elevation(target.x, target.z) + (6 if index == 2 else 3)
	distance = [380.0, 650.0, 74.0][index]
	pitch = [0.68, 0.87, 0.35][index]
	yaw = [0.38, 0.1, 0.4][index]
	label.text = ["울산왜성 | 학성공원 석축 유구", "언양읍성 | 성곽과 남문", "언양읍성 | 영화루 · 옹성"][index] + "\n1: 울산왜성 / 2: 언양읍성 / 3: 영화루\n드래그: 회전 / 휠: 확대"
	_update_camera()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_1, KEY_2, KEY_3]:
		_show(event.keycode - KEY_1)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.006, 0.08, 1.45)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(20, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(1600, distance / 0.9)
	_update_camera()

func _capture() -> void:
	for i in range(3):
		_show(i)
		for frame in range(8):
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var filename: String = ["ulsan_waeseong", "eonyang_eupseong", "eonyang_gate"][i]
		var error := image.save_png(ProjectSettings.globalize_path("res://../results/" + filename + "_preview.png"))
		if error != OK:
			get_tree().quit(1)
			return
	get_tree().quit(0)

func _exit_tree() -> void:
	if is_instance_valid(terrain):
		terrain.free()
