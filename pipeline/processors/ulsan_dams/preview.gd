extends SceneTree

var index := 0
var catalog: Dictionary
var model: Node3D
var world: Node3D
var camera: Camera3D
var frames := 0
var patch: Node3D
var show_terrain := false

func _initialize() -> void:
	_setup.call_deferred()

func _setup() -> void:
	show_terrain = "--terrain" in OS.get_cmdline_user_args()
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	world=Node3D.new()
	root.add_child(world)
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color(.76,.79,.81)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=.35
	environment.environment=settings
	world.add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-28,0)
	sun.light_energy=1.0
	world.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	_show()

func _show() -> void:
	var spec: Dictionary=catalog.models[index]
	model=(load("res://"+str(spec.id)+".tscn") as PackedScene).instantiate()
	world.add_child(model)
	if show_terrain:
		model.scale.x = float(spec.axis_length_m)/float(spec.official_length_m)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file("res://"+str(spec.id)+"_terrain.glb",state)==OK)
		patch = document.generate_scene(state)
		world.add_child(patch)
		for child in patch.find_children("*","MeshInstance3D",true,false):
			var instance := child as MeshInstance3D
			for surface in instance.mesh.get_surface_count():
				var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
				material.albedo_color=Color(.10,.26,.31) if material.resource_name=="water" else Color(.25,.30,.22)
		var sampler := preload("res://terrain_fixture.gd").new()
		sampler.data = JSON.parse_string(FileAccess.get_file_as_string("res://"+str(spec.id)+"_terrain.json"))
		preload("res://dam_terrain_fit.gd").apply(model,sampler)
		sampler.free()
	var length: float=spec.official_length_m
	var height: float=spec.official_height_m
	camera.size=maxf(length,height*4.2)*1.65
	var target := Vector3(0,-height*.5,0)
	camera.position=target+Vector3(length*.65,height*3.5,length*.9)
	camera.look_at(target)
	frames=0

func _process(_delta: float) -> bool:
	frames+=1
	if frames==10:
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var suffix := "_placement_preview.png" if show_terrain else "_preview.png"
	root.get_texture().get_image().save_png("res://"+str(catalog.models[index].id)+suffix)
	model.free()
	if is_instance_valid(patch):
		patch.free()
	index+=1
	if index==catalog.models.size():
		print("DAMS_PREVIEW_OK")
		quit()
	else:
		_show()
