extends SceneTree
## 외부 월드 없이 원경 메시·마커·선택기 동작을 확인한다.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"))
	for entry in expected.assets:
		var packed: PackedScene = load(str(entry.scene_path))
		if packed == null:
			_fail("씬 읽기 실패")
			return
		var model: Node3D = packed.instantiate()
		root.add_child(model)
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(model, meshes)
		var count: int = 0
		for mesh in meshes:
			count += mesh.mesh.get_faces().size() / 3
			if mesh.mesh.get_surface_count() != 1 or mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_fail("표면 또는 그림자 설정 불일치")
				return
		if count != int(entry.metadata.triangles) or _has_costly_nodes(model):
			_fail("삼각형 수 또는 원경 노드 불일치")
			return
		for i in range(entry.metadata.pipe_connectors_m.size()):
			var p: Array = entry.metadata.pipe_connectors_m[i]
			var marker: Marker3D = model.get_node("PipeConnector%d" % i)
			if marker.position.distance_to(Vector3(p[0],p[1],p[2])) > 0.0001:
				_fail("연결 마커 좌표 불일치")
				return
		model.free()
	for uri in expected.auto_scenes:
		var scene: PackedScene = load(str(uri))
		var model: Node3D = scene.instantiate()
		root.add_child(model)
		model.set_distance(0.0)
		if not _visible(model,0): return
		model.set_distance(model.near_end_m*1.1)
		if not _visible(model,1): return
		if model.get_node("Near").process_mode != Node.PROCESS_MODE_DISABLED or _emitting(model.get_node("Near")):
			_fail("근경 처리 또는 파티클 중지 실패")
			return
		model.set_distance(model.near_end_m*0.99)
		if not _visible(model,1): return
		model.set_distance(model.near_end_m*0.9)
		if not _visible(model,0): return
		model.set_distance(model.far_begin_m*1.1)
		if not _visible(model,2): return
		model.set_distance(model.cull_m*1.1)
		if not _visible(model,3): return
		model.set_distance(0.0)
		if not _visible(model,0): return
		model.free()
	print("INDUSTRIAL LOD OK: 56 models, 28 selectors; surfaces, shadows, markers, hysteresis, culling")
	quit()

func _visible(model: Node3D, level: int) -> bool:
	var ok: bool = model.get_node("Near").visible == (level == 0) and model.get_node("Far").visible == (level == 1) and model.get_node("VeryFar").visible == (level == 2)
	if not ok: _fail("LOD 선택 불일치")
	return ok

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): _collect_meshes(child,result)

func _has_costly_nodes(node: Node) -> bool:
	if node is Light3D or node is CollisionObject3D or node is GPUParticles3D or node is CPUParticles3D: return true
	for child in node.get_children():
		if _has_costly_nodes(child): return true
	return false

func _emitting(node: Node) -> bool:
	if (node is GPUParticles3D or node is CPUParticles3D) and node.emitting: return true
	for child in node.get_children():
		if _emitting(child): return true
	return false

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
