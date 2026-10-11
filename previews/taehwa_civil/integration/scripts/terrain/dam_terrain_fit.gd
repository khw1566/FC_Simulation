extends RefCounted

## 이미 DEM에 포함된 제방을 덮는 상부·사면만 지표 위로 맞춘다.
## 원본 래스터와 공유 메시 리소스는 수정하지 않는다.
static func apply(model: Node3D, terrain: Node3D) -> void:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var original := instance.mesh
		var fitted := ArrayMesh.new()
		for surface in original.get_surface_count():
			var arrays: Array = original.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index in vertices.size():
				if normals[index].y < 0.05:
					continue
				var point := instance.to_global(vertices[index])
				var ground: float = terrain.call("get_terrain_elevation", point.x, point.z)
				point.y = maxf(point.y, ground + 0.45)
				vertices[index] = instance.to_local(point)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var single := ArrayMesh.new()
			single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var tool := SurfaceTool.new()
			tool.create_from(single,0)
			tool.generate_normals()
			tool.commit(fitted)
			fitted.surface_set_material(surface, original.surface_get_material(surface))
		instance.mesh = fitted
		var collides := false
		for body in instance.get_children():
			if body is StaticBody3D:
				collides=true
				body.free()
		if collides:
			instance.create_trimesh_collision()
