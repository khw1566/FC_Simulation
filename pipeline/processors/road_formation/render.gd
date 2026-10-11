extends SceneTree
const Grader = preload("res://scripts/terrain/road_formation_grader.gd")
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")
const Batch = preload("res://scripts/terrain/road_batch_builder.gd")
const Host = preload("res://check_host.gd")
var image: Image
var scene: Node3D
var report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960,640)
	image = Image.create(33,33,false,Image.FORMAT_RF)
	for z in 33:
		for x in 33:
			image.set_pixel(x,z,Color((20.0+(x*4.0-64.0)*.1+(z*4.0-64.0)*.3)/100.0,0,0))
	for formed in [false,true]:
		_build(formed)
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "res://after.png" if formed else "res://before.png"
		assert(root.get_texture().get_image().save_png(path)==OK)
		scene.queue_free()
		await process_frame
	report.renderer = "forward_plus"
	report.device = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open("res://render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ROAD_RENDER_OK ",JSON.stringify(report))
	quit()

func _build(formed: bool) -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.13,.13,.13)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	scene.add_child(environment)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(65,65,90)
	camera.fov = 45.0
	camera.look_at(Vector3(0,20,0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65,-25,0)
	scene.add_child(light)
	var grader := Grader.new()
	grader.configure("res://fixture/source.json")
	var request := {"image":image,"grid_res":4,"size":128.0,"center":Vector3.ZERO,"elev_min":0.0,"elev_max":100.0,
		"grader":null,"road_grader":grader if formed else null,"collision":false}
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,Mesher.compute(request).arrays)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	var land := ShaderMaterial.new()
	land.shader = load("res://shaders/procedural_terrain.gdshader")
	land.set_shader_parameter("min_height",0.0)
	land.set_shader_parameter("max_height",100.0)
	land.set_shader_parameter("world_size_meters",128.0)
	land.set_shader_parameter("simple_contour_mode",true)
	land.set_shader_parameter("simple_land_color",Color(.3,.3,.3,1))
	var dry := Image.create(2,2,false,Image.FORMAT_RF)
	dry.fill(Color(0,0,0))
	land.set_shader_parameter("water_mask_texture",ImageTexture.create_from_image(dry))
	terrain.material_override = land
	scene.add_child(terrain)
	var host := Host.new()
	var road := ShaderMaterial.new()
	road.shader = load("res://shaders/road_surface.gdshader")
	road.set_shader_parameter("road_heightmap",ImageTexture.create_from_image(image))
	var lod := Image.create(1,1,false,Image.FORMAT_RF)
	lod.fill(Color(0,0,0))
	road.set_shader_parameter("terrain_lods",ImageTexture.create_from_image(lod))
	road.set_shader_parameter("chunk_counts",Vector2.ONE)
	road.set_shader_parameter("world_size",128.0)
	road.set_shader_parameter("terrain_base_resolution",4.0)
	road.set_shader_parameter("min_elevation",0.0)
	road.set_shader_parameter("max_elevation",100.0)
	road.set_shader_parameter("clearance",.85)
	host.road_material = road
	scene.add_child(host)
	var ground := func(x,z,_fallback):
		var p := Vector3(x,20.0+x*.1+z*.3,z)
		return grader.corrected_height(p) if formed else p.y
	var water := func(_x,_z): return 0.0
	Batch.attach(host,Batch.compute([{"type":"residential","width":8.0,"points":[[-60,14,0],[60,26,0]],"structure_tags_verified":true}],ground,water,Vector2(32,32),Vector2(-64,-64),formed))
