extends SceneTree
## 야간 철로·열차를 경량 독립 프로젝트에서 렌더한다.

var world: Node3D
var model: Node3D
var camera: Camera3D
var index := 0
var frame := 0
const SHOTS = [
	["ktx_track", "rail_1500m", Vector3(900, 250, -1200), Vector3(0, 2, 185)],
	["ktx_night_scene", "ktx_near", Vector3(24, 7, -55), Vector3(0, 2, 36)],
	["ktx_night_scene", "ktx_1500m", Vector3(450, 140, -1350), Vector3(0, 2, 185)],
	["donghae_night_scene", "donghae_1500m", Vector3(150, 60, -1450), Vector3(0, 2, 40)]
]

func _initialize() -> void:
	world = Node3D.new()
	root.add_child.call_deferred(world)
	call_deferred("_setup")

func _setup() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.005, 0.007, 0.012)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.12, 0.16, 0.23)
	env.environment.ambient_light_energy = 0.05
	world.add_child(env)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48
	camera.far = 14000
	world.add_child(camera)
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 3000)
	floor_node.mesh = plane
	floor_node.position = Vector3(0, -0.2, 200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.18, 0.18)
	floor_node.material_override = material
	world.add_child(floor_node)
	DirAccess.make_dir_recursive_absolute("res://captures")

func _process(_delta: float) -> bool:
	if camera == null:
		return false
	frame += 1
	if frame == 5:
		if model != null:
			model.free()
		model = (load("res://assets/generated/railway/night_assets/%s.scn" % SHOTS[index][0]) as PackedScene).instantiate()
		world.add_child(model)
		camera.position = SHOTS[index][2]
		camera.look_at(SHOTS[index][3], Vector3.UP)
	if frame == 20:
		var image := root.get_texture().get_image()
		image.save_png("res://captures/%s.png" % SHOTS[index][1])
		print("NIGHT RENDER: ", SHOTS[index][1])
		index += 1
		frame = 0
		if index == SHOTS.size():
			quit(0)
	return false
