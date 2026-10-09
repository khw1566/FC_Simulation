extends SceneTree
const Batches = preload("res://scripts/vegetation/tree_batch_factory.gd")
var frames := 0
var ready_scene := false
func _initialize() -> void:
	call_deferred("_setup")
func _setup() -> void:
	var transforms: Array[Transform3D] = []
	for i in range(10000):
		transforms.append(Transform3D(Basis.IDENTITY,Vector3((i%100)*5,0,(i/100)*5)))
	var forest := Batches.build("broadleaf",transforms)
	assert(forest.get_child_count() == 192, "64개 청크의 3 LOD 묶음 확인")
	var total := 0
	for child in forest.get_children():
		total += child.multimesh.instance_count
	assert(total == 30000, "LOD별 1만 그루 위치 보존")
	forest.free()
	print("TREE BATCH PASS: 10000 positions, 64 chunks, 192 LOD batches")
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12,0.15,0.18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.45
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	world.add_child(sun)
	var kinds := ["broadleaf","slender","conifer","shrub"]
	for row in range(4):
		for lod in range(3):
			var model = load("res://assets/generated/trees/%s_lod%d.scn" % [kinds[row],lod]).instantiate()
			model.position = Vector3(lod*14,0,row*16)
			world.add_child(model)
			var label := Label3D.new()
			label.text = "%s / LOD%d" % [kinds[row],lod]
			label.position = model.position + Vector3(0,-1,0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 32
			label.pixel_size = 0.025
			world.add_child(label)
	var camera := Camera3D.new()
	camera.position = Vector3(14,30,84)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 60
	world.add_child(camera)
	camera.look_at(Vector3(14,4,24))
	camera.current = true
	ready_scene = true
func _process(_delta: float) -> bool:
	if not ready_scene:
		return false
	frames += 1
	if frames == 25:
		root.get_texture().get_image().save_png("res://tree_preview.png")
		print("TREE PREVIEW OK")
		quit(0)
	return false
