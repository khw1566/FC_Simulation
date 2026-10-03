extends RefCounted
## 렌더링 후보와 물리 충돌을 구분하여 중앙 광선의 대상을 조사한다.
var _face_cache: Dictionary = {}

func inspect(camera: Camera3D, excluded: RID) -> Dictionary:
	var origin := camera.global_position
	var direction := -camera.global_basis.z.normalized()
	var end := origin + direction * camera.far
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [excluded]
	var collision := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var candidates: Array = []
	for id in RenderingServer.instances_cull_ray(origin, end, camera.get_world_3d().scenario):
		var object = instance_from_id(id)
		if not object is MeshInstance3D or not object.is_visible_in_tree() or object.mesh == null:
			continue
		var inverse: Transform3D = object.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_end: Vector3 = inverse * end
		var box_hit = object.get_aabb().intersects_segment(local_origin, local_end)
		if box_hit == null:
			continue
		candidates.append({"node": object, "distance": origin.distance_to(object.global_transform * box_hit)})
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	var hits: Array = []
	for candidate in candidates.slice(0, 8):
		var mesh_node: MeshInstance3D = candidate.node
		var key: int = mesh_node.mesh.get_instance_id()
		if not _face_cache.has(key):
			if _face_cache.size() >= 16:
				_face_cache.clear()
			_face_cache[key] = mesh_node.mesh.get_faces()
		var faces: PackedVector3Array = _face_cache[key]
		var inverse := mesh_node.global_transform.affine_inverse()
		var start: Vector3 = inverse * origin
		var ray: Vector3 = (inverse.basis * direction).normalized()
		var nearest: float = INF
		var position := Vector3.ZERO
		for i in range(0, faces.size(), 3):
			var point = Geometry3D.ray_intersects_triangle(start, ray, faces[i], faces[i + 1], faces[i + 2])
			if point == null:
				continue
			var world: Vector3 = mesh_node.global_transform * point
			var distance: float = origin.distance_to(world)
			if distance < nearest and distance <= camera.far:
				nearest = distance
				position = world
		if nearest < INF:
			var material: Material = mesh_node.material_override
			if material == null and mesh_node.mesh.get_surface_count() > 0:
				material = mesh_node.get_active_material(0)
			var material_name := "재질 없음"
			if material is ShaderMaterial and material.shader != null:
				material_name = material.shader.resource_path
			elif material != null:
				material_name = material.resource_path if not material.resource_path.is_empty() else material.get_class()
			hits.append({"path": str(mesh_node.get_path()), "distance": nearest, "position": position, "material": material_name})
	hits.sort_custom(func(a, b): return a.distance < b.distance)
	return {"collision": collision, "render_hits": hits, "candidate_count": candidates.size()}
