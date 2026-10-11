extends SceneTree
const Geometry = preload("res://scripts/vegetation/bamboo_geometry.gd")
const SPECS = [["bamboo_single",9.0,3.0],["bamboo_clump",9.0,4.5],["bamboo_grove",9.0,9.0]]
func _initialize() -> void:
	var assets := {}
	for spec in SPECS:
		for lod in range(3):
			var id := "%s_lod%d" % [spec[0],lod]
			var node := Geometry.build(spec[0],lod)
			var root_node := Node3D.new()
			root_node.name = id
			root_node.add_child(node)
			node.owner = root_node
			var packed := PackedScene.new()
			assert(packed.pack(root_node) == OK)
			var path := "res://assets/generated/bamboo/%s.scn" % id
			assert(ResourceSaver.save(packed,path) == OK)
			var triangles := int(node.mesh.surface_get_array_len(0) / 3)
			assert(node.mesh.get_surface_count() == 1)
			assets[id] = {"file_path":path,"format":"SCN","type":"bamboo_lod","sha256":FileAccess.get_sha256(path),"size_bytes":FileAccess.get_file_as_bytes(path).size(),"metadata":{"kind":spec[0],"lod":lod,"triangles":triangles,"surfaces":1,"height_m":spec[1],"width_m":spec[2],"bbox":null,"resolution":null,"elevation_min":0,"elevation_max":spec[1],"collision":false}}
			print(id, ": ", triangles, " triangles, 1 surface")
			root_node.free()
		var automatic := Node3D.new()
		automatic.name = str(spec[0]) + "_auto_lod"
		for lod in range(3):
			var node := Geometry.build(spec[0],lod)
			node.name = "LOD%d" % lod
			node.visibility_range_begin = [0.0,70.0,250.0][lod]
			node.visibility_range_end = [70.0,250.0,2200.0][lod]
			if lod > 0:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			automatic.add_child(node)
			node.owner = automatic
		var packed := PackedScene.new()
		assert(packed.pack(automatic) == OK)
		var id := str(spec[0]) + "_auto_lod"
		var path := "res://assets/generated/bamboo/%s.scn" % id
		assert(ResourceSaver.save(packed,path) == OK)
		assets[id] = {"file_path":path,"format":"SCN","type":"bamboo_auto_lod","sha256":FileAccess.get_sha256(path),"size_bytes":FileAccess.get_file_as_bytes(path).size(),"metadata":{"kind":spec[0],"height_m":spec[1],"width_m":spec[2],"bbox":null,"resolution":null,"elevation_min":0,"elevation_max":spec[1],"collision":false,"lod_ranges_m":[[0,70],[70,250],[250,2200]]}}
		automatic.free()
	var file := FileAccess.open("res://assets/generated/bamboo/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"assets":assets},"  "))
	quit(0)
