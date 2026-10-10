extends SceneTree
const Geometry = preload("res://scripts/vegetation/forest_tree_geometry.gd")
const KINDS = ["deciduous_a","deciduous_b","deciduous_c","pine_a","pine_b","pine_c","shrub_a","shrub_b","shrub_c","bamboo_a","bamboo_b","bamboo_c"]
const RANGES = [[0.0,100.0],[100.0,350.0],[350.0,1500.0]]
func _initialize() -> void:
	var assets := {}
	for kind in KINDS:
		var data: Array = Geometry.spec(kind)
		for lod in range(3):
			var id := "%s_lod%d" % [kind,lod]
			var node := Geometry.build(kind,lod)
			var root_node := Node3D.new()
			root_node.name = id
			root_node.add_child(node)
			node.owner = root_node
			var packed := PackedScene.new()
			assert(packed.pack(root_node) == OK)
			var path := "res://assets/generated/forest_trees/%s.scn" % id
			assert(ResourceSaver.save(packed,path) == OK)
			var triangles := int(node.mesh.surface_get_array_len(0) / 3)
			assets[id] = {"file_path":path,"format":"SCN","type":"forest_tree_lod","sha256":FileAccess.get_sha256(path),"size_bytes":FileAccess.get_file_as_bytes(path).size(),"metadata":{"kind":kind,"lod":lod,"triangles":triangles,"surfaces":1,"species":data[0],"height_m":data[1],"width_m":data[2],"bbox":null,"resolution":null,"elevation_min":0,"elevation_max":data[1],"collision":false}}
			print(id, ": ", triangles, " triangles")
			root_node.free()
		var automatic := Node3D.new()
		automatic.name = kind + "_auto_lod"
		for lod in range(3):
			var node := Geometry.build(kind,lod)
			node.name = "LOD%d" % lod
			node.visibility_range_begin = RANGES[lod][0]
			node.visibility_range_end = RANGES[lod][1]
			automatic.add_child(node)
			node.owner = automatic
		var packed := PackedScene.new()
		assert(packed.pack(automatic) == OK)
		var id: String = str(kind) + "_auto_lod"
		var path := "res://assets/generated/forest_trees/%s.scn" % id
		assert(ResourceSaver.save(packed,path) == OK)
		assets[id] = {"file_path":path,"format":"SCN","type":"forest_tree_auto_lod","sha256":FileAccess.get_sha256(path),"size_bytes":FileAccess.get_file_as_bytes(path).size(),"metadata":{"kind":kind,"species":data[0],"height_m":data[1],"width_m":data[2],"bbox":null,"resolution":null,"elevation_min":0,"elevation_max":data[1],"collision":false,"lod_ranges_m":RANGES}}
		automatic.free()
	var file := FileAccess.open("res://assets/generated/forest_trees/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"assets":assets},"  "))
	quit(0)
