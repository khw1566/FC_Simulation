extends SceneTree
const Geometry = preload("res://scripts/vegetation/silvergrass_geometry.gd")
const KINDS = ["silvergrass_clump","silvergrass_patch","reed_patch"]
const RANGES = [[0.0,40.0],[40.0,150.0],[150.0,900.0]]
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
			var path := "res://assets/generated/silvergrass/%s.scn" % id
			assert(ResourceSaver.save(packed,path) == OK)
			var triangles := int(node.mesh.surface_get_array_len(0) / 3)
			assets[id] = {"file_path":path,"format":"SCN","type":"silvergrass_lod","sha256":FileAccess.get_sha256(path),"size_bytes":FileAccess.get_file_as_bytes(path).size(),"metadata":{"kind":kind,"lod":lod,"triangles":triangles,"surfaces":1,"height_m":data[0],"width_m":data[1],"bbox":null,"resolution":null,"elevation_min":0,"elevation_max":data[0],"collision":false}}
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
		var path := "res://assets/generated/silvergrass/%s.scn" % id
		assert(ResourceSaver.save(packed,path) == OK)
		assets[id] = {"file_path":path,"format":"SCN","type":"silvergrass_auto_lod","sha256":FileAccess.get_sha256(path),"size_bytes":FileAccess.get_file_as_bytes(path).size(),"metadata":{"kind":kind,"height_m":data[0],"width_m":data[1],"bbox":null,"resolution":null,"elevation_min":0,"elevation_max":data[0],"collision":false,"lod_ranges_m":RANGES}}
		automatic.free()
	var file := FileAccess.open("res://assets/generated/silvergrass/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"assets":assets},"  "))
	quit(0)
