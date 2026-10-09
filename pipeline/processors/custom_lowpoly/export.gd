extends SceneTree
## 원본 활주로 프레임을 보존하며 공항과 성곽의 기하만 다시 만든다.
const Heritage = preload("res://scripts/terrain/heritage_model_builder.gd")
const Airport = preload("res://scripts/terrain/airport_mesh_builder.gd")
const Regional = preload("res://scripts/terrain/regional_airport_mesh_builder.gd")
const Surfaces = preload("res://scripts/terrain/airfield_surface_builder.gd")

func _initialize() -> void:
	var heritage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://ulsan_heritage_models.json"))
	for spec in heritage.landmarks:
		save(Heritage.new().build(spec), spec.scene_path)
	var japan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://japan_airports.json"))
	for spec in japan.airports:
		save(Regional.new().build(spec), spec.scene_path)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://ulsan_airport_model.json"))
	var model := Airport.new().build(spec)
	var path := "res://assets/generated/airport/ulsan_airport.scn"
	var old := (load(path.replace("res://", "res://originals/")) as PackedScene).instantiate()
	var airfield := old.get_node("RunwayFrame").duplicate() as Node3D
	var previous := airfield.get_node("AirfieldSurfaces")
	airfield.remove_child(previous)
	previous.free()
	airfield.add_child(Surfaces.new().build(spec))
	model.add_child(airfield)
	save(model, path)
	old.free()
	quit()

func save(node: Node3D, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	owners(node, node)
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	print("EXPORTED: ", path)
	node.free()

func owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		owners(child, owner_node)
