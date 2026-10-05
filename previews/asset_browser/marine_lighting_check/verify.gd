extends SceneTree
const Factory = preload("res://scripts/water/vessel_model_factory.gd")
const Wake = preload("res://scripts/water/vessel_wake.gd")
var environment: Environment
var sun: DirectionalLight3D
var frame := 0

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var entry := {"type":"tugboat", "length_m":30.0, "beam_m":10.0, "glb_path":"res://assets/generated/vessels/tugboat.glb"}
	var ship := Factory.new().instantiate(entry)
	assert(ship != null)
	world.add_child(ship)
	var lights := 0
	for child in ship.get_children():
		if child is Light3D:
			lights += 1
	assert(lights == 1, "선박 광원 누락 또는 과잉")
	var wake := Wake.new()
	world.add_child(wake)
	wake.configure(entry, {})
	for i in range(60):
		wake.advance(0.4, Transform3D(Basis.IDENTITY, Vector3(0, 0, (59 - i) * 2.0)), 5.0)
	assert(wake.mesh != null)
	var bridge = load("res://assets/generated/pedestrian_bridges/generic_pedestrian_overpass.scn").instantiate()
	bridge.position = Vector3(30, 0, 0)
	world.add_child(bridge)
	assert(bridge.has_node("BridgeLighting"))
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.025, 0.045, 0.065)
	mat.roughness = 0.8
	water.material_override = mat
	world.add_child(water)
	var env := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.015, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.3, 0.35, 0.4)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	world.add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(45, 25, 55)
	camera.look_at(Vector3(10, 0, 10))
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://captures")

func _process(_delta: float) -> bool:
	if sun == null:
		return false
	frame += 1
	if frame == 20:
		root.get_texture().get_image().save_png("res://captures/day.png")
		sun.light_energy = 0.0
		environment.ambient_light_energy = 0.05
	if frame == 40:
		root.get_texture().get_image().save_png("res://captures/night.png")
		print("MARINE PASS: ship one local light, bridge lighting, day/night wake rendered")
		quit(0)
	return false
