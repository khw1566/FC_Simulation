extends SceneTree
## 수종 12형태 × 3 LOD 비교 이미지와 MultiMesh 묶음 구조 확인.
const Batches = preload("res://scripts/vegetation/vegetation_batch_factory.gd")
const KINDS = ["deciduous_a","deciduous_b","deciduous_c","pine_a","pine_b","pine_c","shrub_a","shrub_b","shrub_c","bamboo_a","bamboo_b","bamboo_c"]
var frames := 0
var ready_scene := false
func _initialize() -> void:
	call_deferred("_setup")
func _setup() -> void:
	var transforms: Array[Transform3D] = []
	for i in range(4096):
		transforms.append(Transform3D(Basis.IDENTITY,Vector3((i%64)*8,0,(i/64)*8)))
	var forest := Batches.build("res://assets/generated/forest_trees/%s_lod%d.scn","deciduous_a",transforms,[[0.0,100.0],[100.0,350.0],[350.0,1500.0]])
	var total := 0
	for child in forest.get_children():
		total += child.multimesh.instance_count
	assert(forest.get_child_count() == 192 and total == 4096 * 3, "64개 청크 × 3 LOD, LOD별 4096개 보존")
	forest.free()
	print("FOREST BATCH PASS: 4096 positions, 64 chunks, 192 LOD batches")
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62,0.72,0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55,0.6,0.45)
	ground.material_override = gm
	world.add_child(ground)
	for k in range(KINDS.size()):
		for lod in range(3):
			var model = load("res://assets/generated/forest_trees/%s_lod%d.scn" % [KINDS[k],lod]).instantiate()
			model.position = Vector3((k % 6) * 13.0 + lod * 0.0, 0, (k / 6) * 0.0) + Vector3(0, 0, lod * 14.0 + (k / 6) * 44.0)
			world.add_child(model)
	var camera := Camera3D.new()
	camera.position = Vector3(32,48,-30)
	world.add_child(camera)
	camera.look_at(Vector3(32,0,42))
	camera.fov = 60
	camera.current = true
	ready_scene = true
func _process(_delta: float) -> bool:
	if not ready_scene:
		return false
	frames += 1
	if frames == 25:
		root.get_texture().get_image().save_png("res://forest_trees_preview.png")
		print("FOREST PREVIEW OK")
		quit(0)
	return false
