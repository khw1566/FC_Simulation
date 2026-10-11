extends SceneTree
const Grader = preload("res://scripts/terrain/road_formation_grader.gd")
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")
const Batch = preload("res://scripts/terrain/road_batch_builder.gd")
const Host = preload("res://check_host.gd")
const OPTIMIZED := false
var evidence: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(320,180)
	for frame in 12:
		await process_frame
	var grader := Grader.new()
	grader.configure("res://fixture/source.json")
	assert(grader.enabled)
	grader.corrected_height(Vector3(0,20,0))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://perf_config.json"))
	var task := WorkerThreadPool.add_task(func():
		for key in config.cold_tiles:
			grader.segments(Rect2(Vector2(key[0]*512,key[1]*512),Vector2(511,511)))
	,false,"노반 타일 부하")
	var lookup_peak := 0.0
	var lookup_count := 0
	while not WorkerThreadPool.is_task_completed(task):
		await process_frame
		var start := Time.get_ticks_usec()
		assert(absf(grader.corrected_height(Vector3(0,20,0))-20.0)<.0001)
		lookup_peak = maxf(lookup_peak,(Time.get_ticks_usec()-start)/1000.0)
		lookup_count += 1
	WorkerThreadPool.wait_for_task_completion(task)
	evidence.cached_height_during_cold_tiles = {"peak_ms":lookup_peak,"queries":lookup_count,"cold_tiles":config.cold_tiles.size()}
	var dense := Grader.new()
	dense.configure("res://dense/source.json")
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dense/config.json"))
	var image := Image.create_from_data(65,65,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://dense/height.bin"))
	var request := {"image":image,"grid_res":8,"size":512.0,"center":Vector3(c.x,0,c.z),"elev_min":0.0,"elev_max":1.0,"grader":null,"road_grader":dense,"collision":false,"upload_pages":OPTIMIZED,"keep_arrays":true}
	var holder: Array = []
	var started := Time.get_ticks_msec()
	task = WorkerThreadPool.add_task(func(): holder.append(Mesher.compute(request)),false,"512m 노반")
	var responsive := 0
	while not WorkerThreadPool.is_task_completed(task):
		await process_frame
		responsive += 1
	WorkerThreadPool.wait_for_task_completion(task)
	var worker_ms := Time.get_ticks_msec()-started
	var arrays: Array = holder[0].arrays
	var upload_ms := 0.0
	var upload_frames := 0
	var page_count := 1
	if OPTIMIZED:
		var uploader = load("res://scripts/terrain/terrain_mesh_upload.gd").new()
		page_count = holder[0].pages.size()
		uploader.begin(root,holder[0].pages,StandardMaterial3D.new())
		while true:
			var upload := Time.get_ticks_usec()
			var done: bool = uploader.step()
			upload_ms = maxf(upload_ms,(Time.get_ticks_usec()-upload)/1000.0)
			if done:
				break
			await process_frame
			upload_frames += 1
	else:
		var mesh := ArrayMesh.new()
		var upload := Time.get_ticks_usec()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		upload_ms = (Time.get_ticks_usec()-upload)/1000.0
	evidence.terrain = {"worker_ms":worker_ms,"responsive_frames":responsive,"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"triangles":arrays[Mesh.ARRAY_INDEX].size()/3,"upload_call_ms":upload_ms,"upload_frames":upload_frames,"pages":page_count,"size_m":512}
	var host := Host.new()
	root.add_child(host)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(0,0,0),Vector3(1,0,0),Vector3(0,0,1)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	var quad := st.commit_to_arrays()
	var result := {"surface_groups":{},"formed_ground":true,"tunnel":[],"bridge":[],"bridge_shapes":[]}
	for i in 2048:
		result.surface_groups[str(i)] = {"kind":"paved","tier":"small","arrays":[quad]}
	var previous := Time.get_ticks_usec()
	var frame_peak := 0.0
	var frames := 0
	var begin := Time.get_ticks_usec()
	var container: Node3D
	if Batch.has_method("attach_streamed"):
		var pending := [null]
		_attach.call_deferred(host,result,pending)
		while pending[0]==null:
			await process_frame
			var now := Time.get_ticks_usec()
			frame_peak = maxf(frame_peak,(now-previous)/1000.0)
			previous = now
			frames += 1
		container = pending[0]
	else:
		container = Batch.attach(host,result)
		frame_peak = (Time.get_ticks_usec()-begin)/1000.0
	assert(container.get_child_count()==2048)
	evidence.roads = {"meshes":2048,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"peak_frame_or_sync_call_ms":frame_peak,"responsive_frames":frames}
	evidence.device = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open("res://measurement.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	print("STREAMING_MEASUREMENT_OK ",JSON.stringify(evidence))
	quit()

func _attach(host: Node3D, result: Dictionary, pending: Array) -> void:
	pending[0] = await Batch.attach_streamed(host,result)
