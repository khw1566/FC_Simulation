extends Node3D

const Builder = preload("res://scripts/terrain/building_mesh_builder.gd")
const Policy = preload("res://scripts/terrain/campus_building_policy.gd")
const Ground = preload("res://scripts/terrain/campus_ground_overlay.gd")
var camera: Camera3D
var target := Vector3.ZERO
var distance := 900.0
var yaw := 0.25
var pitch := 0.8
var heightmap: Image

func _ready() -> void:
	heightmap = Image.load_from_file("res://assets/maps/ulsan_uc_west/ulsan_heightmap_16bit.png")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/ulsan_uc_west/buildings_and_roads.json"))
	var candidates: Array = []
	Policy.mark_imagery_candidates(data.get("buildings", []))
	for building in data.get("buildings", []):
		if Policy.is_campus_candidate(building):
			candidates.append(building)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78,0.76,0.72)
	Builder.build_chunk_buildings_mesh(candidates, self, material, _ground)
	var terrain := SurfaceTool.new()
	terrain.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-850, 851, 10):
		for x in range(-850, 651, 10):
			for p in [Vector2(x,z),Vector2(x+10,z),Vector2(x,z+10),Vector2(x+10,z),Vector2(x+10,z+10),Vector2(x,z+10)]:
				terrain.add_vertex(Vector3(p.x,_ground(p.x,p.y,0),p.y))
	terrain.generate_normals()
	var ground := MeshInstance3D.new()
	ground.mesh = terrain.commit()
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.29,0.34,0.26)
	grass.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = grass
	add_child(ground)
	Ground.build(self, _ground)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.14,0.16,0.18)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-25,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2500
	add_child(sun)
	camera = Camera3D.new()
	camera.far = 8000
	add_child(camera)
	camera.make_current()
	target = Vector3(-180,55,-140)
	distance = 1150.0
	if "--college" in OS.get_cmdline_user_args():
		target = Vector3(-440,75,-630)
		distance = 420.0
	_update_camera()
	print("CAMPUS_BUILDINGS=", candidates.size())
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(24,20)
	label.text = "울산대학교 · 울산과학대 서부캠퍼스 | 창작 모델 초안\n드래그: 회전 / 휠: 확대 / 1: 전체 / 2: 서부캠퍼스 / 3: 울산대학교\n영상: 국토교통부 브이월드 · 입면·부지·계단은 근사 표현"
	label.add_theme_font_size_override("font_size",18)
	layer.add_child(label)
	add_child(layer)
	if "--capture-campus" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _ground(x: float, z: float, fallback: float) -> float:
	if heightmap == null or heightmap.is_empty():
		return fallback
	var px := clampi(int((x / 5000.0 + 0.5) * (heightmap.get_width()-1)),0,heightmap.get_width()-1)
	var pz := clampi(int((z / 5000.0 + 0.5) * (heightmap.get_height()-1)),0,heightmap.get_height()-1)
	return heightmap.get_pixel(px,pz).r * 460.0 - 10.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			target = Vector3(-180,55,-140)
			distance = 1150
		elif event.keycode == KEY_2:
			target = Vector3(-440,75,-630)
			distance = 420
		elif event.keycode == KEY_3:
			target = Vector3(-90,45,50)
			distance = 650
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006,0.1,1.5)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance *= 0.9
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance *= 1.1
	_update_camera()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target)

func _capture() -> void:
	for i in range(6):
		await RenderingServer.frame_post_draw
	var filename := "ulsan_college_draft.png" if "--college" in OS.get_cmdline_user_args() else "ulsan_campus_draft.png"
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../results/" + filename))
	get_tree().quit(error)
