extends SceneTree

const Builder = preload("res://scripts/terrain/airport_mesh_builder.gd")
const Layout = preload("res://scripts/terrain/airfield_layout.gd")
const Surfaces = preload("res://scripts/terrain/airfield_surface_builder.gd")
const Lights = preload("res://scripts/terrain/airfield_light_builder.gd")

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Godot 4.3 더미 렌더러는 MultiMesh 좌표를 저장하지 않습니다. --headless 없이 --rendering-method gl_compatibility 옵션으로 생성하세요.")
		quit(1)
		return
	_build.call_deferred()

func _build() -> void:
	var project_root := ProjectSettings.globalize_path("res://").get_base_dir()
	var source_path := project_root.path_join("../config/ulsan_airport_model.json").simplify_path()
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		push_error("공항 모델 설정을 읽을 수 없습니다: " + source_path)
		quit(1)
		return
	var spec: Dictionary = JSON.parse_string(file.get_as_text())
	var model: Node3D = Builder.new().build(spec)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/ulsan_metro_80km/map_meta.json"))
	var airfield := Node3D.new()
	airfield.name = "RunwayFrame"
	airfield.transform = Layout.local_frame(spec, meta)
	airfield.add_child(Surfaces.new().build(spec))
	airfield.add_child(Lights.new().build(spec))
	model.add_child(airfield)
	await RenderingServer.frame_post_draw
	_set_owner(model, model)
	var packed := PackedScene.new()
	var error := packed.pack(model)
	var asset_dir := "res://assets/generated/airport"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset_dir))
	if error == OK:
		error = ResourceSaver.save(packed, asset_dir + "/ulsan_airport.scn")
	if error != OK:
		push_error("공항 모델 저장 실패: " + str(error))
		model.free()
		quit(1)
		return
	spec["scene_path"] = asset_dir + "/ulsan_airport.scn"
	var output := FileAccess.open(asset_dir + "/placement.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(spec, "  "))
	output.close()
	var indexer = load(project_root.path_join("../pipeline/indexer/airport_asset_indexer.gd").simplify_path()).new()
	indexer.update(spec, model)
	print("공항 모델 생성 완료: ", asset_dir, " / 노드 수: ", model.find_children("*", "", true, false).size())
	model.free()
	quit(0)

func _set_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_owner(child, scene_root)

