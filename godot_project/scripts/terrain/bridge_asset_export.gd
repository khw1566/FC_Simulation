extends SceneTree

## 독립 씬을 생성하는 오프라인 진입점. 실행 중 지형 배치는 매니저가 담당한다.
const Builder = preload("res://scripts/terrain/bridge_landmark_builder.gd")

func _initialize() -> void:
	var folder := "res://assets/generated/bridges"
	DirAccess.make_dir_recursive_absolute(folder)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/taehwa_bridges.json"))
	var specs: Array = data.bridges.duplicate(true)
	specs.append({"name": "generic_river_bridge", "kind": "beam", "width_m": 12.0, "preview_length_m": 120.0, "pier_spacing_m": 30.0})
	specs.append({"name": "taehwa_stepping_stones", "kind": "stepping_stones", "width_m": 1.25, "preview_length_m": 60.0})
	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var curve := Curve3D.new()
		if spec.has("geometry"):
			var origin: Dictionary = spec.geometry[0]
			for point in spec.geometry:
				curve.add_point(Vector3((float(point.lon) - float(origin.lon)) * 90307.04, 0.0, (float(origin.lat) - float(point.lat)) * 110987.79))
		else:
			curve.add_point(Vector3.ZERO)
			curve.add_point(Vector3(0, 0, float(spec.preview_length_m)))
		var model := Builder.build(spec, curve, null)
		get_root().add_child(model)
		own_children(model, model)
		var packed := PackedScene.new()
		var error := packed.pack(model)
		if error == OK:
			error = ResourceSaver.save(packed, folder.path_join("bridge_%02d.scn" % i))
		if error != OK:
			push_error("교량 씬 저장 실패: " + str(spec.name))
			quit(1)
			return
		model.free()
	print("Bridge assets exported: ", specs.size())
	quit()

func own_children(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		own_children(child, root)
