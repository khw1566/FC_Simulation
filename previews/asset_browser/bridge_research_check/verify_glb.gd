extends SceneTree
## 원본 임포터 없이 GLTFDocument로 인덱스 메시를 읽는다.
func _initialize() -> void:
	var metrics: Array = JSON.parse_string(FileAccess.get_file_as_string("res://glb_metrics.json"))
	for item in metrics:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file("res://" + str(item.path), state)
		if error != OK:
			push_error("GLB 읽기 실패: " + str(item.path))
			quit(1)
			return
		var node := document.generate_scene(state)
		if node == null or triangles(node) != int(item.after.triangles):
			push_error("GLB 삼각형 수 불일치: " + str(item.path))
			quit(2)
			return
		node.free()
	print("GLB READ OK: ", metrics.size())
	quit()

func triangles(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += node.mesh.get_faces().size() / 3
	for child in node.get_children():
		count += triangles(child)
	return count
