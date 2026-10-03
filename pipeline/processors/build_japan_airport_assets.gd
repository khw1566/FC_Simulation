extends SceneTree
const Builder = preload("res://scripts/terrain/regional_airport_mesh_builder.gd")
const Layout = preload("res://scripts/terrain/regional_airport_layout.gd")

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	var config_path := "res://../config/japan_airports.json"
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	var folder := "res://assets/generated/japan_airports"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var manifest_path := "res://assets/generated/manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	for spec in catalog.airports:
		var model := Builder.new().build(spec)
		_own(model, model)
		var scene := PackedScene.new()
		if scene.pack(model) != OK or ResourceSaver.save(scene, spec.scene_path) != OK:
			push_error("공항 저장 실패: " + str(spec.id))
			quit(1)
			return
		var bounds := Layout.bounds(spec)
		var lon_step := 111320.0 * cos(deg_to_rad(float(spec.anchor.lat)))
		var bbox := {"west": float(spec.anchor.lon) + bounds.position.x / lon_step, "east": float(spec.anchor.lon) + bounds.end.x / lon_step,
			"north": float(spec.anchor.lat) - bounds.position.y / 111320.0, "south": float(spec.anchor.lat) - bounds.end.y / 111320.0}
		manifest.assets["japan_airport_" + str(spec.id)] = {"file_path": spec.scene_path, "sha256": FileAccess.get_sha256(spec.scene_path),
			"size_bytes": FileAccess.get_file_as_bytes(spec.scene_path).size(), "bbox": bbox, "elevation": {"min_meters": -2, "max_meters": 36},
			"resolution": {"type": "batched_procedural_mesh", "runways": spec.runways.size(), "units": "meters"}, "accuracy": spec.accuracy}
		model.free()
	_write(folder + "/placement.json", catalog)
	manifest.assets["japan_airport_catalog"] = {"file_path": folder + "/placement.json", "sha256": FileAccess.get_sha256(folder + "/placement.json"),
		"bbox": {"south": 30.9, "north": 34.5, "west": 129.5, "east": 132.0}, "elevation": {"min_meters": 0, "max_meters": 700},
		"resolution": {"type": "airport_catalog", "airports": catalog.airports.size()}}
	_write(manifest_path, manifest)
	print("일본 공항 모델 생성 완료: ", catalog.airports.size())
	quit(0)

func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_own(child, scene_root)

func _write(path: String, value: Dictionary) -> void:
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(value, "  "))
