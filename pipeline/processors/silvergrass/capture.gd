extends SceneTree
## 억새·갈대 3종 × 3 LOD 비교 이미지와 MultiMesh 묶음 구조 확인.
const Batches = preload("res://scripts/vegetation/vegetation_batch_factory.gd")
var frames := 0
var ready_scene := false
func _initialize() -> void:
	call_deferred("_setup")
func _setup() -> void:
	var transforms: Array[Transform3D] = []
	for i in range(4096):
		transforms.append(Transform3D(Basis.IDENTITY,Vector3((i%64)*4,0,(i/64)*4)))
	var field := Batches.build("res://assets/generated/silvergrass/%s_lod%d.scn","silvergrass_patch",transforms,[[0.0,40.0],[40.0,150.0],[150.0,900.0]],false)
	var total := 0
	for child in field.get_children():
		total += child.multimesh.instance_count
	assert(field.get_child_count() == 48 and total == 4096 * 3, "16개 청크 × 3 LOD, LOD별 4096개 보존")
	field.free()
	print("SILVERGRASS BATCH PASS: 4096 positions, 16 chunks, 48 LOD batches")
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12,0.15,0.18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	world.add_child(sun)
	var kinds := ["silvergrass_clump","silvergrass_patch","reed_patch"]
	for row in range(3):
		for lod in range(3):
			var model = load("res://assets/generated/silvergrass/%s_lod%d.scn" % [kinds[row],lod]).instantiate()
			model.position = Vector3(lod*5.5,(2-row)*3.6,0)
			world.add_child(model)
			var label := Label3D.new()
			label.text = "%s / LOD%d" % [kinds[row],lod]
			label.position = model.position + Vector3(0,-0.35,0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 32
			label.pixel_size = 0.008
			world.add_child(label)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.5
	camera.position = Vector3(5.5,5.0,30)
	world.add_child(camera)
	camera.look_at(Vector3(5.5,4.6,0))
	camera.current = true
	ready_scene = true
func _process(_delta: float) -> bool:
	if not ready_scene:
		return false
	frames += 1
	if frames == 25:
		root.get_texture().get_image().save_png("res://silvergrass_preview.png")
		print("SILVERGRASS PREVIEW OK")
		quit(0)
	return false
