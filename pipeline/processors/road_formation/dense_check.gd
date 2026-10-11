extends SceneTree
const Grader = preload("res://scripts/terrain/road_formation_grader.gd")
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dense/config.json"))
	var grader := Grader.new()
	grader.configure("res://dense/source.json")
	assert(grader.enabled)
	var center := Vector3(config.x,0,config.z)
	var image := Image.create_from_data(65,65,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://dense/height.bin"))
	var request := {"image":image,"grid_res":2,"size":128.0,"center":center,"elev_min":0.0,"elev_max":1.0,"grader":null,"road_grader":grader,"collision":false}
	var started := Time.get_ticks_msec()
	var result := Mesher.compute(request)
	var elapsed := Time.get_ticks_msec()-started
	var vertices: PackedVector3Array = result.arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = result.arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	for p in vertices:
		assert(p.is_finite())
	for i in range(0,indices.size(),3):
		var a := Vector2(vertices[indices[i]].x,vertices[indices[i]].z)
		var b := Vector2(vertices[indices[i+1]].x,vertices[indices[i+1]].z)
		var c := Vector2(vertices[indices[i+2]].x,vertices[indices[i+2]].z)
		area += absf((b-a).cross(c-a))*.5
	assert(absf(area-16384)<1.0)
	var all_segments: Array = grader.segments(Rect2(Vector2(center.x-64,center.z-64),Vector2(128,128)))
	var probes: Array[Vector3] = []
	for z in 16:
		for x in 16:
			var p := center+Vector3(x*8.0-60.0,30,z*8.0-60.0)
			assert(absf(grader.corrected_height(p)-grader.corrected_height(p,all_segments))<.0001)
			probes.append(p)
	var query_started := Time.get_ticks_usec()
	for p in probes:
		grader.corrected_height(p)
	var query_ms := (Time.get_ticks_usec()-query_started)/1000.0
	var report := {"size_m":128,"segments":config.segments,"build_ms":elapsed,"vertices":vertices.size(),"triangles":indices.size()/3,"projected_area_m2":area,
		"point_bucket_probes":probes.size(),"cached_point_queries_ms":query_ms}
	var file := FileAccess.open("res://dense.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("DENSE_ROAD_CHECK_OK ",JSON.stringify(report))
	quit()
