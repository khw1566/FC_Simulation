extends SceneTree

const Civil = preload("res://scripts/terrain/taehwa_civil_manager.gd")
const Water = preload("res://scripts/water/taehwa_water_manager.gd")
const BASE := "res://assets/generated/taehwa_civil/"
var world: Node3D
var camera: Camera3D
var water: Node3D
var civil: Node3D

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    world = Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(.22,.39,.54)
    sky_mat.sky_horizon_color = Color(.70,.77,.79)
    sky_mat.ground_horizon_color = Color(.70,.77,.79)
    sky.sky_material = sky_mat
    env.sky = sky
    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = .45
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    environment.environment = env
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-43,-35,0)
    sun.light_energy = .8
    sun.shadow_enabled = true
    world.add_child(sun)
    var terrain := ShaderMaterial.new()
    terrain.shader = load("res://shaders/procedural_terrain.gdshader")
    var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"bed_patch.json"))
    var r: Array = meta.world_rect
    var mask := ImageTexture.create_from_image(Image.load_from_file(BASE+"overlay_mask.png"))
    terrain.set_shader_parameter("river_overlay_mask",mask)
    terrain.set_shader_parameter("river_overlay_rect",Vector4(r[0],r[1],r[2],r[3]))
    terrain.set_shader_parameter("has_river_overlay",true)
    var black := Image.create(2,2,false,Image.FORMAT_RGBA8)
    black.fill(Color.BLACK)
    terrain.set_shader_parameter("water_mask_texture",ImageTexture.create_from_image(black))
    terrain.set_shader_parameter("world_size_meters",80000.0)
    terrain.set_shader_parameter("simple_contour_mode",true)
    terrain.set_shader_parameter("simple_land_color",Color(.30,.32,.27))
    terrain.set_shader_parameter("contour_thickness",.25)
    water = Water.new()
    world.add_child(water)
    await water.setup("ulsan_metro_80km",terrain)
    civil = Civil.new()
    world.add_child(civil)
    civil.setup({"id":"ulsan_metro_80km"})
    for spec in ["bancheon","yeocheon"]:
        var node := load("res://"+spec+"_terrain.tscn") as PackedScene
        var instance := node.instantiate()
        instance.material_override = terrain
        world.add_child(instance)
    camera = Camera3D.new()
    camera.far = 5000
    camera.near = .15
    world.add_child(camera)
    camera.current = true
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
    var a: Array = catalog.models[0].anchor_world_m
    var center := Vector3(a[0],a[1],a[2])
    camera.position = center+Vector3(-75,65,105)
    camera.look_at(center+Vector3(0,-.2,5),Vector3.UP)
    await capture("bancheon_weir")
    camera.position = center+Vector3(-18,5,-65)
    camera.look_at(center+Vector3(20,-.7,-20),Vector3.UP)
    water.water_material.set_shader_parameter("simulation_time",0.0)
    await capture("water_flow_0")
    water.water_material.set_shader_parameter("simulation_time",2.0)
    await capture("water_flow_2")
    for surface in water.find_children("Water","MeshInstance3D",true,false):surface.visible = false
    await capture("water_hidden")
    for surface in water.find_children("Water","MeshInstance3D",true,false):surface.visible = true
    a = catalog.models[1].anchor_world_m
    center = Vector3(a[0],a[1],a[2])
    camera.position = center+Vector3(-320,620,470)
    camera.look_at(center,Vector3.UP)
    await capture("yeocheon_basin")
    a = catalog.models[2].anchor_world_m
    center = Vector3(a[0],a[1],a[2])
    camera.position = center+Vector3(-40,24,55)
    camera.look_at(center+Vector3(0,1,0),Vector3.UP)
    await capture("yeocheon_gate")
    print("TAEHWA_RENDER_OK")
    quit()

func capture(label: String) -> void:
    for frame in range(12):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://"+label+".png")
