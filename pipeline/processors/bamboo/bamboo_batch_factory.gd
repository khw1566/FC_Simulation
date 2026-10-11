extends RefCounted
## 동일 수종·LOD를 64m 청크별 MultiMesh로 묶는다.
static func build(kind: String, transforms: Array[Transform3D], chunk_size: float = 64.0) -> Node3D:
	var root := Node3D.new()
	root.name = "BambooBatches"
	var groups := {}
	for pose in transforms:
		var key := Vector2i(floori(pose.origin.x/chunk_size),floori(pose.origin.z/chunk_size))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pose)
	for lod in range(3):
		var packed := load("res://assets/generated/bamboo/%s_lod%d.scn" % [kind,lod]) as PackedScene
		if packed == null:
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
			node.visibility_range_begin = [0.0,70.0,250.0][lod]
			node.visibility_range_end = [70.0,250.0,2200.0][lod]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(node)
		template.free()
	return root
