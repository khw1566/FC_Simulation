extends SceneTree

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	var metrics: Array = []
	for spec in catalog.models:
		var assembly := Node3D.new()
		assembly.name = str(spec.id)
		var faces := 0
		for lod in ["near","far"]:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var error := document.append_from_file("res://%s_%s.glb" % [spec.id,lod], state)
			if error != OK:
				push_error("댐 GLB 읽기 실패")
				quit(1)
				return
			var node := document.generate_scene(state)
			node.name = lod
			assembly.add_child(node)
			for child in node.find_children("*","MeshInstance3D",true,false):
				var mesh := child as MeshInstance3D
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
					var color: Array = catalog.palette[str(material.resource_name)]
					material.albedo_color=Color(color[0],color[1],color[2])
					material.roughness=1.0
				mesh.visibility_range_begin = 3500.0 if lod == "far" else 0.0
				mesh.visibility_range_end = 24000.0 if lod == "far" else 3500.0
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if lod == "near":
					mesh.create_trimesh_collision()
					faces += mesh.mesh.get_faces().size()/3
		_set_owners(assembly,assembly)
		var packed := PackedScene.new()
		if packed.pack(assembly) != OK or ResourceSaver.save(packed,"res://"+str(spec.id)+".tscn") != OK:
			quit(1)
			return
		metrics.append({"id":spec.id,"near_triangles":faces})
		assembly.free()
	var file := FileAccess.open("res://bake_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t"))
	print("DAMS_BAKE_OK ",metrics.size())
	quit()

func _set_owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owners(child,owner_node)
