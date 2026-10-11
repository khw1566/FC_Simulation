extends Node3D

var _camera: Camera3D
var _yaw: float = 0.38
var _pitch: float = 0.42
var _distance: float = 330.0
var _target := Vector3(65, 6, 0)
var _settings: Environment
var _sun: DirectionalLight3D
var _airfield_target: Vector3
var _night: bool = false

func _ready() -> void:
	var model := load("res://assets/generated/airport/ulsan_airport.scn") as PackedScene
	var instance := model.instantiate()
	add_child(instance)
	_airfield_target = instance.get_node("RunwayFrame").transform * Vector3(90, 0, -900)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	_settings = settings
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.12, 0.14, 0.16)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.82, 0.86, 0.92)
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 800
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3700, 1500)
	ground.mesh = plane
	ground.position = Vector3(_airfield_target.x, -1.5, _airfield_target.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.26, 0.27)
	ground.material_override = material
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 48
	_camera.near = 2.0
	_camera.far = 12000
	add_child(_camera)
	_camera.make_current()
	_overview()
	_update_camera()
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.text = "울산공항 | 활주로 18 / 36\n2,000 × 45m · 유도로 · 계류장 · 항공등화\n드래그: 회전 / 휠: 확대 / 1: 청사 / 2: 전체 / N: 주야간\n공식 치수와 좌표 기반 · 유도로와 진입등 배열은 근사 표현"
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	add_child(layer)
	if "--night-airfield" in OS.get_cmdline_user_args():
		_toggle_night()
	if "--capture-airport" in OS.get_cmdline_user_args() or "--capture-airfield" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_target = Vector3(35, 6, 0)
			_distance = 250
			_pitch = 0.42
			_yaw = 0.38
		elif event.keycode == KEY_2:
			_overview()
		elif event.keycode == KEY_N:
			_toggle_night()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.006, 0.1, 1.4)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(70, _distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(6000, _distance / 0.9)
	_update_camera()

func _update_camera() -> void:
	_camera.position = _target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(_target)

func _overview() -> void:
	_target = _airfield_target
	_distance = 2300
	_pitch = 1.03
	_yaw = 0.12

func _toggle_night() -> void:
	_night = not _night
	_settings.background_color = Color(0.008, 0.012, 0.025) if _night else Color(0.12, 0.14, 0.16)
	_settings.ambient_light_energy = 0.12 if _night else 0.65
	_sun.light_energy = 0.05 if _night else 1.0

func _capture() -> void:
	for i in range(5):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var filename := "ulsan_airfield_night.png" if _night else "ulsan_airfield_day.png"
	var path := ProjectSettings.globalize_path("res://../results/" + filename)
	var result := image.save_png(path)
	print("공항 미리보기 저장: ", result, " ", path)
	get_tree().quit(result)

