extends SceneTree
const Scatter = preload("res://scripts/vegetation/ecozone_scatter.gd")
class FakeMap:
	var id := "taehwagang_dunchi"
	var world_size_meters := 8000.0
	var bbox_south := 35.515
	var bbox_north := 35.5872
	var bbox_west := 129.2738
	var bbox_east := 129.3622
class FakeTerrain extends Node3D:
	var terrain_material: ShaderMaterial
	var load_complete := true
	var load_error := ""
	func get_terrain_elevation(_x: float, _z: float) -> float:
		return 5.0
var frames := 0
var shots := []
var camera: Camera3D
func _initialize() -> void:
	call_deferred("_setup")
func _setup() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62,0.72,0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.55
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-35,0)
	world.add_child(sun)
	var terrain := FakeTerrain.new()
	terrain.terrain_material = ShaderMaterial.new()
	terrain.terrain_material.shader = load("res://shaders/procedural_terrain.gdshader")
	terrain.terrain_material.set_shader_parameter("world_size_meters", 8000.0)
	var black := Image.create(64, 64, false, Image.FORMAT_L8)
	terrain.terrain_material.set_shader_parameter("water_mask_texture", ImageTexture.create_from_image(black))
	world.add_child(terrain)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8000,8000)
	pm.subdivide_width = 200
	pm.subdivide_depth = 200
	plane.mesh = pm
	plane.position.y = 5.0
	plane.material_override = terrain.terrain_material
	world.add_child(plane)
	var node := Scatter.new()
	node.terrain_manager = terrain
	world.add_child(node)
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(Scatter.CATALOG))
	node.configure_mapping(catalog, FakeMap.new())
	node.bind_ground()
	node.add_forest_masses()
	for layer in catalog.layers:
		node.add_layer(layer, catalog.families[layer.family])
	print("RENDER SETUP: placed ", node.placed_count, " canopy ", node.mass_count, " ground ", node.ground_bound)
	camera = Camera3D.new()
	camera.far = 20000
	world.add_child(camera)
	camera.current = true
	# 국가정원 곡류부(원천 x≈-2000, z≈150) 원경·근경, 명촌 억새 근경
	shots = [[Vector3(2819,7.5,-3720),Vector3(2819,5.5,-3660),"near_silvergrass"],[Vector3(2819,40,-3900),Vector3(2819,5,-3500),"low_silvergrass"],[Vector3(2700,180,-3950),Vector3(2850,5,-3550),"far_silvergrass"],[Vector3(3100,250,-1800),Vector3(3234,5,-2105),"far2_silvergrass"]]
	_shot(0)
func _shot(i: int) -> void:
	camera.position = shots[i][0]
	camera.look_at(shots[i][1])
func _process(_d: float) -> bool:
	if camera == null:
		return false
	frames += 1
	if frames % 40 == 0:
		var index: int = frames / 40 - 1
		root.get_texture().get_image().save_png("res://shot_%s.png" % shots[index][2])
		if index + 1 >= shots.size():
			quit(0)
		else:
			_shot(index + 1)
	return false
