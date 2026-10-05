extends SceneTree
## 터널 정적 씬과 자산 메타데이터를 저장한다.

const Builder = preload("res://scripts/terrain/railway_tunnel_asset_builder.gd")
const OUTPUT := "res://assets/generated/railway_tunnels"
var entries: Dictionary = {}
var catalog: Array[Dictionary] = []

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://railway_tunnel_assets.json"))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for definition in config.profiles:
		var profile: Dictionary = config.defaults.duplicate(true)
		profile.merge(definition, true)
		profile.accuracy = config.accuracy
		for part in ["entry", "body", "exit"]:
			var spec := Builder.part_spec(profile, part)
			if not save_model(Builder.build(spec), spec, false):
				quit(1)
				return
		var model := Builder.assembled(profile)
		var set_spec := profile.duplicate(true)
		set_spec.id = str(profile.id) + "_tunnel_set"
		set_spec.name_ko = str(profile.name_ko) + " 연결 세트"
		set_spec.length_m = model.get_meta("length_m")
		set_spec.part = "assembled"
		if not save_model(model, set_spec, false):
			quit(2)
			return
		var inspection := Builder.assembled(profile)
		_hide_lining(inspection)
		set_spec.id = str(profile.id) + "_tunnel_inspection"
		set_spec.name_ko = str(profile.name_ko) + " 내부 구조 확인용"
		inspection.name = str(set_spec.id)
		inspection.set_meta("label_ko", set_spec.name_ko)
		if not save_model(inspection, set_spec, true):
			quit(3)
			return
	_write_json("manifest.json", {"version": 1, "assets": entries})
	_write_json("catalog.json", {"version": 1, "models": catalog})
	quit(0)

func save_model(model: Node3D, spec: Dictionary, inspection: bool) -> bool:
	root.add_child(model)
	_own_children(model, model)
	var packed := PackedScene.new()
	var path := OUTPUT.path_join(str(spec.id) + ".scn")
	if packed.pack(model) != OK or ResourceSaver.save(packed, path) != OK:
		push_error("터널 에셋 저장 실패: " + str(spec.id))
		return false
	var state := {"first": true, "bounds": AABB(), "triangles": 0, "collisions": 0}
	_measure(model, Transform3D.IDENTITY, state)
	var bounds: AABB = state.bounds
	var metadata := {"label_ko": spec.name_ko, "part": spec.part, "track_bed": spec.track_bed,
		"length_m": spec.length_m, "inner_width_m": float(spec.inner_half_width_m) * 2.0,
		"inner_height_m": spec.inner_height_m, "gauge_m": spec.gauge_m, "track_spacing_m": spec.track_spacing_m,
		"rail_top_y_m": spec.rail_top_y_m, "connection_axis": "+Z", "track_count": 2,
		"aabb_min_m": [bounds.position.x, bounds.position.y, bounds.position.z],
		"aabb_max_m": [bounds.end.x, bounds.end.y, bounds.end.z],
		"bbox": null, "resolution": null, "elevation_min": bounds.position.y, "elevation_max": bounds.end.y,
		"triangles": state.triangles, "collision_shapes": state.collisions,
		"accuracy": spec.accuracy, "placement_status": "asset_only", "inspection_only": inspection}
	if model.has_meta("connections"):
		metadata.connections = model.get_meta("connections")
	entries[str(spec.id)] = {"file_path": path, "format": "SCN",
		"type": "railway_tunnel_inspection" if inspection else "railway_tunnel_model",
		"sha256": FileAccess.get_sha256(path), "size_bytes": FileAccess.get_file_as_bytes(path).size(), "metadata": metadata}
	catalog.append({"id": spec.id, "name_ko": spec.name_ko, "scene_path": path, "inspection_only": inspection})
	var check := (load(path) as PackedScene).instantiate()
	var delta: Vector3 = check.get_node("TrackEnd").position - check.get_node("TrackStart").position
	if delta.distance_to(Vector3(0, 0, float(spec.length_m))) > 0.001 or int(state.collisions) == 0:
		push_error("터널 연결점 또는 충돌 저장 실패")
		return false
	check.free()
	print("EXPORTED: ", spec.id, " / ", state.triangles, " triangles")
	model.free()
	return true

func _hide_lining(node: Node) -> void:
	if node is MeshInstance3D and node.name in ["lining", "joints"]:
		node.visible = false
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_hide_lining(child)

func _measure(node: Node, parent_pose: Transform3D, state: Dictionary) -> void:
	var pose := parent_pose
	if node is Node3D:
		pose = parent_pose * node.transform
	if node is MeshInstance3D:
		var box: AABB = pose * node.get_aabb()
		state.bounds = box if state.first else state.bounds.merge(box)
		state.first = false
		state.triangles += node.mesh.get_faces().size() / 3
	elif node is CollisionShape3D:
		state.collisions += 1
	for child in node.get_children():
		_measure(child, pose, state)

func _own_children(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_children(child, owner_node)

func _write_json(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(OUTPUT.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
