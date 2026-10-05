extends SceneTree
## 야간 조명이 적용된 열차·철로와 독립 조립 예제를 저장한다.

const Train = preload("res://scripts/terrain/railway_train_builder.gd")
const Track = preload("res://scripts/terrain/railway_track_builder.gd")
const OUTPUT := "res://assets/generated/railway/night_assets"
var entries: Dictionary = {}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var services: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/railway/services.json"))
	for profile in services.services:
		var train := _train(profile)
		_save(train, str(profile.id) + "_train", str(profile.name) + " 야간 조명 열차")
		var rail := _track(profile)
		_save(rail, str(profile.id) + "_track", str(profile.name) + " 야간 식별 철로")
		var scene := Node3D.new()
		scene.name = str(profile.id) + "_night_scene"
		scene.add_child(_train(profile))
		scene.add_child(_track(profile))
		_save(scene, str(profile.id) + "_night_scene", str(profile.name) + " 야간 조명 조립 예제")
	var file := FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "assets": entries}, "  "))
	file.close()
	quit(0)

func _train(profile: Dictionary) -> Node3D:
	var train := Train.build(profile)
	var distance := 0.0
	for index in range(train.get_child_count()):
		var car := train.get_child(index) as Node3D
		var length := float(profile.car_length_m)
		if str(profile.id) == "ktx" and index in [0, train.get_child_count() - 1]:
			length = float(profile.get("power_car_length_m", length))
		car.position.z = distance + length * 0.5
		distance += length + float(profile.car_gap_m)
	train.set_meta("cars", int(profile.cars))
	return train

func _track(profile: Dictionary) -> Node3D:
	return Track.build(PackedVector3Array([Vector3(0, 0, -60), Vector3(0, 0, 460)]), profile, {"bridge": false}, 12000.0)

func _save(node: Node3D, id: String, label: String) -> void:
	root.add_child(node)
	node.set_meta("label_ko", label)
	_owners(node, node)
	var packed := PackedScene.new()
	var path := OUTPUT.path_join(id + ".scn")
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	var state := {"lights": 0, "markers": 0, "first": true, "bounds": AABB()}
	_measure(node, Transform3D.IDENTITY, state)
	assert(int(state.lights) > 0 and int(state.markers) > 0, "야간 광원 및 표시 누락")
	var bounds: AABB = state.bounds
	entries[id] = {"file_path": path, "format": "SCN", "type": "railway_night_asset",
		"sha256": FileAccess.get_sha256(path), "size_bytes": FileAccess.get_file_as_bytes(path).size(),
		"metadata": {"label_ko": label, "bbox": null, "resolution": null,
		"aabb_min_m": [bounds.position.x, bounds.position.y, bounds.position.z],
		"aabb_max_m": [bounds.end.x, bounds.end.y, bounds.end.z],
		"elevation_min": bounds.position.y, "elevation_max": bounds.end.y,
		"light_count": state.lights, "marker_batches": state.markers, "placement_status": "asset_only"}}
	print("NIGHT ASSET: ", id, " / lights=", state.lights, " markers=", state.markers)
	node.free()

func _owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_owners(child, owner_node)

func _measure(node: Node, previous: Transform3D, state: Dictionary) -> void:
	var pose := previous
	if node is Node3D:
		pose = previous * node.transform
	if node is Light3D:
		state.lights += 1
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var bounds: AABB = pose * node.get_aabb()
		state.bounds = bounds if state.first else state.bounds.merge(bounds)
		state.first = false
		if node.material_override is StandardMaterial3D and node.material_override.get_flag(BaseMaterial3D.FLAG_FIXED_SIZE):
			state.markers += 1
	for child in node.get_children():
		_measure(child, pose, state)
