extends SceneTree
## 맵을 로딩하지 않는 교량 에셋 오프라인 생성 진입점.

const Crossing = preload("res://scripts/terrain/gulhwa_crossing_asset.gd")
const Seonbawi = preload("res://scripts/terrain/seonbawi_bridge_asset.gd")
const Overpass = preload("res://scripts/terrain/pedestrian_overpass_asset.gd")
const OUTPUT := "res://assets/generated/pedestrian_bridges"

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pedestrian_bridge_assets.json"))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var entries: Dictionary = {}
	for spec in config.assets:
		var model: Node3D
		match str(spec.id):
			"gulhwa_daun_crossing": model = Crossing.build(spec)
			"seonbawi_bridge": model = Seonbawi.build(spec)
			"generic_pedestrian_overpass": model = Overpass.build(spec)
		model.set_meta("label_ko", spec.name_ko)
		model.set_meta("accuracy", spec.accuracy)
		model.set_meta("units", "meters")
		root.add_child(model)
		_own_children(model, model)
		var packed := PackedScene.new()
		var scene_path := OUTPUT.path_join(str(spec.id) + ".scn")
		if packed.pack(model) != OK or ResourceSaver.save(packed, scene_path) != OK:
			push_error("교량 씬 저장 실패: " + str(spec.id))
			quit(1)
			return
		var triangles := 0
		var bounds := AABB()
		var first := true
		for node in model.get_children():
			if node is MeshInstance3D:
				triangles += node.mesh.get_faces().size() / 3
				bounds = node.get_aabb() if first else bounds.merge(node.get_aabb())
				first = false
		entries[str(spec.id)] = {"file_path": scene_path, "format": "SCN", "type": "bridge_model",
			"sha256": FileAccess.get_sha256(scene_path), "size_bytes": FileAccess.get_file_as_bytes(scene_path).size(),
			"metadata": {"label_ko": spec.name_ko, "length_m": spec.length_m, "width_m": spec.width_m,
			"deck_height_m": spec.deck_height_m, "triangles": triangles,
			"aabb_min_m": [bounds.position.x, bounds.position.y, bounds.position.z],
			"aabb_max_m": [bounds.end.x, bounds.end.y, bounds.end.z], "bbox": null, "resolution": null,
			"elevation_min": bounds.position.y, "elevation_max": bounds.end.y,
			"accuracy": spec.accuracy, "source_urls": spec.source_urls, "placement_status": "asset_only"}}
		print("EXPORTED: ", spec.id, " / ", triangles, " triangles")
		var reloaded := load(scene_path) as PackedScene
		if reloaded == null:
			quit(2)
			return
		var check := reloaded.instantiate()
		if check.get_child_count() == 0:
			quit(3)
			return
		check.free()
		model.free()
	var file := FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "assets": entries}, "  "))
	file.close()
	quit(0)

func _own_children(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_children(child, owner_node)
