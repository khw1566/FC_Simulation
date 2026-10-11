extends SceneTree
## 접속점·광원·기존 충돌을 보존하고 실제 반복 인스턴스 수를 집계한다.
var metrics: Array = []
var materials: Dictionary = {}

func _initialize() -> void:
	var paths: Array = JSON.parse_string(FileAccess.get_file_as_string("res://paths.json"))
	for relative in paths:
		var path: String = "res://" + str(relative)
		var old := (load("res://originals/" + str(relative)) as PackedScene).instantiate()
		var node := (load(path) as PackedScene).instantiate()
		var before := measure(old)
		restore_collision(old, node)
		for key in old.get_meta_list():
			node.set_meta(key, old.get_meta(key))
		simplify(node, str(relative).ends_with("_night_scene.scn"))
		node.set_meta("detail_profile", "rail_bridge_low_poly_v1")
		node.set_meta("material_style", "flat_color")
		owners(node, node)
		var packed := PackedScene.new()
		assert(packed.pack(node) == OK)
		assert(ResourceSaver.save(packed, path) == OK)
		var checked := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		assert(signature(old) == signature(checked), "접속점·광원·충돌 변경: " + path)
		var after := measure(checked)
		assert(after.triangles <= before.triangles, "삼각형 증가: " + path)
		metrics.append({"path": relative, "before": before, "after": after,
			"before_bytes": FileAccess.get_file_as_bytes("res://originals/" + str(relative)).size(),
			"after_bytes": FileAccess.get_file_as_bytes(path).size(), "sha256": FileAccess.get_sha256(path)})
		print(relative, ": ", before.triangles, " -> ", after.triangles)
		old.free()
		node.free()
		checked.free()
	var file := FileAccess.open("res://metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "  "))
	quit()

func restore_collision(old: Node, node: Node) -> void:
	for child in node.get_children():
		if child is PhysicsBody3D:
			node.remove_child(child)
			child.free()
		else:
			var corresponding := old.get_node_or_null(NodePath(str(child.name)))
			if corresponding:
				restore_collision(corresponding, child)
	for child in old.get_children():
		if child is PhysicsBody3D:
			node.add_child(child.duplicate())

func owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		owners(child, owner_node)

func simplify(node: Node, assembly: bool = false) -> void:
	# 조립 예제의 열차 하위 재질은 수정하지 않는다.
	for child in node.get_children():
		if assembly and child is Node3D and absf(child.position.z + 60.0) > 0.001:
			continue
		simplify(child)
	if node is MeshInstance3D:
		if node.material_override is StandardMaterial3D:
			node.material_override = flat(node.material_override)
		elif node.mesh:
			for surface in node.mesh.get_surface_count():
				var material: Material = node.get_active_material(surface)
				if material is StandardMaterial3D:
					node.set_surface_override_material(surface, flat(material))
	elif node is MultiMeshInstance3D:
		var material: Material = node.material_override
		if material == null and node.multimesh and node.multimesh.mesh:
			material = node.multimesh.mesh.surface_get_material(0)
		if material is StandardMaterial3D:
			node.material_override = flat(material)

func flat(original: StandardMaterial3D) -> StandardMaterial3D:
	var key := original.get_instance_id()
	if materials.has(key):
		return materials[key]
	var material := original.duplicate() as StandardMaterial3D
	material.metallic = 0.0
	material.roughness = 1.0
	if material.albedo_texture is GradientTexture2D:
		var texture := material.albedo_texture.duplicate() as GradientTexture2D
		texture.width = 8
		texture.height = 8
		material.albedo_texture = texture
	elif not material.get_flag(BaseMaterial3D.FLAG_FIXED_SIZE):
		material.albedo_texture = null
		material.normal_enabled = false
		material.roughness_texture = null
		material.metallic_texture = null
		if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			material.albedo_color.a = 1.0
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	materials[key] = material
	return material

func signature(node: Node) -> Array:
	var entries: Array[String] = []
	_collect_signature(node, Transform3D.IDENTITY, entries)
	entries.sort()
	return entries

func _collect_signature(node: Node, previous: Transform3D, entries: Array[String]) -> void:
	var pose := previous
	if node is Node3D:
		pose = previous * node.transform
	if node is Marker3D:
		entries.append("marker:" + str(node.name) + ":" + str(pose))
	elif node is Light3D:
		entries.append("light:" + str(node.get_class()) + ":" + str(pose) + ":" + str(node.light_energy))
	elif node is CollisionShape3D:
		entries.append("collision:" + str(pose) + ":" + str(var_to_bytes(node.shape.get("data") if node.shape is ConcavePolygonShape3D else node.shape.get("size"))))
	for child in node.get_children():
		_collect_signature(child, pose, entries)

func measure(node: Node) -> Dictionary:
	var state := {"triangles": 0, "mesh_nodes": 0, "instances": 0, "collisions": 0, "first": true, "bounds": AABB()}
	_measure(node, Transform3D.IDENTITY, state)
	var bounds: AABB = state.bounds
	state.erase("bounds")
	state.erase("first")
	state["aabb_min_m"] = [bounds.position.x, bounds.position.y, bounds.position.z]
	state["aabb_max_m"] = [bounds.end.x, bounds.end.y, bounds.end.z]
	return state

func _measure(node: Node, previous: Transform3D, state: Dictionary) -> void:
	var pose := previous
	if node is Node3D:
		pose = previous * node.transform
	if node is CollisionShape3D:
		state.collisions += 1
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
		var instances: int = 1 if node is MeshInstance3D else node.multimesh.instance_count
		state.triangles += int(mesh.get_faces().size() / 3) * instances
		state.instances += instances
		state.mesh_nodes += 1
		var bounds: AABB = pose * node.get_aabb()
		state.bounds = bounds if state.first else state.bounds.merge(bounds)
		state.first = false
	for child in node.get_children():
		_measure(child, pose, state)
