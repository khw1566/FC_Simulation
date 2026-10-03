extends SceneTree

const Builder = preload("res://scripts/terrain/heritage_model_builder.gd")
const OUTPUT := "res://assets/generated/heritage"

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var source := "res://../config/ulsan_heritage_models.json"
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var index_path := "res://assets/generated/manifest.json"
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	for item in spec.landmarks:
		var model := Builder.new().build(item)
		var bounds := AABB()
		var first := true
		var triangles := 0
		for child in model.get_children():
			child.owner = model
			bounds = child.get_aabb() if first else bounds.merge(child.get_aabb())
			first = false
			triangles += child.mesh.get_faces().size() / 3
		var packed := PackedScene.new()
		var error := packed.pack(model)
		if error == OK:
			error = ResourceSaver.save(packed, item.scene_path)
		if error != OK:
			push_error("성곽 모델 저장 실패: " + str(error))
			model.free()
			quit(1)
			return
		var lon_m := 111320.0 * cos(deg_to_rad(float(item.anchor.lat)))
		index.assets[item.id + "_custom_model"] = {
			"file_path": item.scene_path, "format": "Godot PackedScene", "sha256": FileAccess.get_sha256(item.scene_path),
			"bbox": {"west": item.anchor.lon + bounds.position.x / lon_m, "east": item.anchor.lon + bounds.end.x / lon_m, "south": item.anchor.lat - bounds.end.z / 111320.0, "north": item.anchor.lat - bounds.position.z / 111320.0},
			"elevation": {"min_meters": bounds.position.y, "max_meters": bounds.end.y, "reference": "지역 지표 기준 높이, 런타임 DEM에 맞춰 배치"},
			"resolution": {"type": "triangle_mesh", "triangles": triangles, "material_batches": model.get_child_count()},
			"metadata": {"name_ko": item.name_ko, "basis": spec.modeling_basis, "sources": spec.sources}
		}
		print(item.id, ": ", triangles, " triangles / ", model.get_child_count(), " batches")
		model.free()
	var placement := FileAccess.open(OUTPUT + "/placement.json", FileAccess.WRITE)
	placement.store_string(JSON.stringify(spec, "  "))
	placement.close()
	index.assets["ulsan_heritage_placement"] = {
		"file_path": OUTPUT + "/placement.json", "format": "JSON", "sha256": FileAccess.get_sha256(OUTPUT + "/placement.json"),
		"bbox": {"west": 129.1206, "east": 129.3412, "south": 35.5531, "north": 35.5699},
		"elevation": {"min_meters": -0.6, "max_meters": 10.2, "reference": "지역 지표 기준, 런타임 DEM 적용"},
		"resolution": {"type": "placement", "landmark_count": spec.landmarks.size()},
		"metadata": {"source_config": source, "source_sha256": FileAccess.get_sha256(source)}
	}
	index["last_updated"] = Time.get_datetime_string_from_system()
	var file := FileAccess.open(index_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(index, "  "))
	file.close()
	quit(0)
