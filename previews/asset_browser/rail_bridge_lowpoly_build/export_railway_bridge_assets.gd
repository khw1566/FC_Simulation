extends SceneTree
## 독립 철도 교량 자산 저장과 접속 규약 검증.

const Builder = preload("res://scripts/terrain/railway_bridge_asset_builder.gd")
const UlsanSet = preload("res://scripts/terrain/ulsan_railway_bridge_set.gd")
const OUTPUT := "res://assets/generated/railway_bridges"
var entries: Dictionary = {}
var catalog: Array[Dictionary] = []

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://railway_bridge_assets.json"))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for definition in config.generic:
		var spec: Dictionary = config.defaults.duplicate(true)
		spec.merge(definition, true)
		if not _save_model(Builder.build(spec), spec):
			quit(1)
			return
	for spec in UlsanSet.specs(config):
		if not _save_model(Builder.build(spec), spec):
			quit(2)
			return
	var set_model := UlsanSet.build(config)
	var set_spec: Dictionary = config.ulsan_set.duplicate(true)
	set_spec.length_m = set_model.get_meta("length_m")
	set_spec.kind = "assembled_set"
	if not _save_model(set_model, set_spec):
		quit(3)
		return
	_write_json("manifest.json", {"version": 1, "assets": entries})
	_write_json("catalog.json", {"version": 1, "models": catalog})
	print("RAILWAY BRIDGES COMPLETE: ", entries.size())
	quit(0)

func _save_model(model: Node3D, spec: Dictionary) -> bool:
	root.add_child(model)
	_own_children(model, model)
	var packed := PackedScene.new()
	var path := OUTPUT.path_join(str(spec.id) + ".scn")
	if packed.pack(model) != OK or ResourceSaver.save(packed, path) != OK:
		push_error("철도 교량 저장 실패: " + str(spec.id))
		return false
	var state := {"first": true, "bounds": AABB(), "triangles": 0, "collision_shapes": 0}
	_measure(model, Transform3D.IDENTITY, state)
	var bounds: AABB = state.bounds
	var metadata := {"label_ko": spec.name_ko, "kind": spec.kind,
		"length_m": spec.length_m, "width_m": spec.width_m,
		"gauge_m": model.get_meta("gauge_m"), "track_count": model.get_meta("track_count"),
		"track_spacing_m": model.get_meta("track_spacing_m"), "rail_top_y_m": model.get_meta("rail_top_y_m"),
		"connection_axis": "+Z", "triangles": state.triangles, "collision_shapes": state.collision_shapes,
		"aabb_min_m": [bounds.position.x, bounds.position.y, bounds.position.z],
		"aabb_max_m": [bounds.end.x, bounds.end.y, bounds.end.z],
		"bbox": null, "resolution": null, "elevation_min": bounds.position.y, "elevation_max": bounds.end.y,
		"accuracy": spec.get("accuracy", "게임용 범용 모델, 치수는 제작 설정값"),
		"source_urls": spec.get("source_urls", []), "placement_status": "asset_only"}
	if model.has_meta("connections"):
		metadata.connections = model.get_meta("connections")
	entries[str(spec.id)] = {"file_path": path, "format": "SCN", "type": "railway_bridge_model",
		"sha256": FileAccess.get_sha256(path), "size_bytes": FileAccess.get_file_as_bytes(path).size(), "metadata": metadata}
	catalog.append({"id": spec.id, "name_ko": spec.name_ko, "scene_path": path, "length_m": spec.length_m})
	var check := (load(path) as PackedScene).instantiate()
	root.add_child(check)
	var start: Vector3 = check.get_node("TrackStart").position
	var end: Vector3 = check.get_node("TrackEnd").position
	var expected := Vector3(0, 0, float(spec.length_m))
	if (end - start).distance_to(expected) > 0.001 or int(state.collision_shapes) < 1:
		push_error("철도 교량 연결점 또는 충돌 형상 검증 실패: " + str(spec.id))
		return false
	print("EXPORTED: ", spec.id, " / ", state.triangles, " triangles / sockets OK")
	check.free()
	model.free()
	return true

func _measure(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var pose := parent_transform
	if node is Node3D:
		pose = parent_transform * node.transform
	if node is MeshInstance3D:
		var box: AABB = pose * node.get_aabb()
		state.bounds = box if state.first else state.bounds.merge(box)
		state.first = false
		state.triangles += node.mesh.get_faces().size() / 3
	elif node is CollisionShape3D:
		state.collision_shapes += 1
	for child in node.get_children():
		_measure(child, pose, state)

func _own_children(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_children(child, owner_node)

func _write_json(filename: String, data: Dictionary) -> void:
	var file := FileAccess.open(OUTPUT.path_join(filename), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
