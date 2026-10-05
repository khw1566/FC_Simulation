extends SceneTree
## 고유 임시 프리뷰 프로젝트에서 터널 입구와 내부 구조를 렌더한다.

var world: Node3D
var camera: Camera3D
var model: Node3D
var index := 0
var frame := 0
const MODELS = ["hsr_tunnel_entry", "donghae_tunnel_entry", "hsr_tunnel_inspection", "donghae_tunnel_inspection"]

func _initialize() -> void:
	world = Node3D.new()
	root.add_child.call_deferred(world)
	call_deferred("_setup")

func _setup() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.06, 0.06)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 1.2
	world.add_child(light)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48
	world.add_child(camera)
	DirAccess.make_dir_recursive_absolute("res://captures")

func _process(_delta: float) -> bool:
	if camera == null:
		return false
	frame += 1
	if frame == 5:
		if model != null:
			model.free()
		model = (load("res://assets/generated/railway_tunnels/%s.scn" % MODELS[index]) as PackedScene).instantiate()
		world.add_child(model)
		if index < 2:
			camera.position = Vector3(16, 11, -24)
			camera.look_at(Vector3(0, 3.5, 2), Vector3.UP)
		else:
			camera.position = Vector3(47, 28, -25)
			camera.look_at(Vector3(0, 1.5, 30), Vector3.UP)
	if frame == 18:
		var image := root.get_texture().get_image()
		if image.save_png("res://captures/%s.png" % MODELS[index]) != OK:
			quit(1)
			return true
		print("CAPTURED: ", MODELS[index])
		index += 1
		frame = 0
		if index == MODELS.size():
			quit(0)
	return false
