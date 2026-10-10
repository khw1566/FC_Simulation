extends RefCounted
## 계열 공통 식생 MultiMesh 묶음기. 씬 경로 템플릿(%s=kind, %d=LOD)과 LOD 거리로 64m 청크별 묶음을 만든다.
static func build(scene_template: String, kind: String, transforms: Array[Transform3D], lod_ranges: Array, shadow_lod0: bool = true, chunk_size: float = 64.0, material_override: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = kind + "_Batches"
	var groups := {}
	for pose in transforms:
		var key := Vector2i(floori(pose.origin.x/chunk_size),floori(pose.origin.z/chunk_size))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pose)
	for lod in range(lod_ranges.size()):
		var packed := load(scene_template % [kind,lod]) as PackedScene
		if packed == null:
			push_warning("식생 LOD 없음: " + scene_template % [kind,lod])
			continue
		var template := packed.instantiate()
		var mesh: Mesh = template.get_child(0).mesh
		for key in groups:
			var origin := Vector3((key.x+0.5)*chunk_size,0,(key.y+0.5)*chunk_size)
			origin.y = groups[key][0].origin.y
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = groups[key].size()
			for i in range(multi.instance_count):
				var pose: Transform3D = groups[key][i]
				pose.origin -= origin
				multi.set_instance_transform(i,pose)
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d_%d_LOD%d" % [kind,key.x,key.y,lod]
			node.position = origin
			node.multimesh = multi
			# 원경 카드(텍스처 알파 컷아웃)는 자체 재질을 유지하고, 정점 색 메시에만 흔들림 재질을 씌운다.
			var own := mesh.surface_get_material(0) as BaseMaterial3D
			if material_override != null and (own == null or own.albedo_texture == null):
				node.material_override = material_override
			node.visibility_range_begin = float(lod_ranges[lod][0])
			node.visibility_range_end = float(lod_ranges[lod][1])
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 and shadow_lod0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(node)
		template.free()
	return root
