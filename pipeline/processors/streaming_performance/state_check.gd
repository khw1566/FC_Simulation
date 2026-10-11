extends SceneTree
const Chunk = preload("res://scripts/terrain/terrain_chunk.gd")
const Pages = preload("res://scripts/terrain/terrain_upload_pages.gd")
const Upload = preload("res://scripts/terrain/terrain_mesh_upload.gd")
const Budget = preload("res://scripts/terrain/stream_frame_budget.gd")
const Buildings = preload("res://scripts/terrain/building_batch_assembler.gd")
const Collisions = preload("res://scripts/terrain/building_collision_stream.gd")
const Host = preload("res://state_host.gd")
const Detail = preload("res://scripts/terrain/road_earthwork_detail.gd")
var report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(load("res://scripts/views/performance_hud.gd").can_instantiate())
	assert(load("res://scripts/testing/prebaked_rail_baker.gd").can_instantiate())
	var field = preload("res://detail_field.gd").new()
	assert(not Detail.needs_split(Vector3.ZERO,Vector3(8,0,0),Vector3(0,0,8),field,[],sqrt(128)))
	field.curved = true
	assert(Detail.needs_split(Vector3.ZERO,Vector3(8,0,0),Vector3(0,0,8),field,[],sqrt(128)))
	report.detail = {"flat_subdivision_skipped":true,"curved_edge_preserved":true,"edge_sample_tolerance_m":Detail.EDGE_ERROR}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point: Vector3 in [Vector3.ZERO,Vector3.RIGHT,Vector3.BACK]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(point.x,point.z))
		st.add_vertex(point)
	st.index()
	var arrays := st.commit_to_arrays()
	# 48,001개 삼각형으로 큰 배열 분할 경계와 정점 속성의 순서를 확인한다.
	var indices := PackedInt32Array()
	for i in 48001:
		indices.append_array(PackedInt32Array([0,1,2]))
	arrays[Mesh.ARRAY_INDEX] = indices
	var pages := Pages.split(arrays)
	assert(pages.size()==4)
	var cursor := 0
	for page: Array in pages:
		assert(page[Mesh.ARRAY_INDEX].size()<=Pages.TRIANGLES*3)
		for i: int in page[Mesh.ARRAY_INDEX]:
			var original: int = indices[cursor]
			for attribute in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]:
				assert(page[attribute][i]==arrays[attribute][original])
			cursor += 1
	assert(cursor==indices.size())
	# 한 메시의 표면 한도를 넘으면 다음 메시로 넘기며 모두 보존한다.
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	var many: Array = []
	for i in 65:
		many.append(arrays)
	var uploader := Upload.new()
	uploader.begin(root,many,StandardMaterial3D.new())
	assert(uploader.step(true) and uploader.meshes.size()==2)
	assert(uploader.meshes[0].mesh.get_surface_count()==64)
	assert(uploader.meshes[1].mesh.get_surface_count()==1)
	uploader.container.queue_free()
	report.pages = {"triangles_preserved":48001,"attributes_preserved":true,"surface_limit_preserved":true}
	var chunk := Chunk.new()
	root.add_child(chunk)
	chunk.base_resolution = 16
	var image := Image.create(17,17,false,Image.FORMAT_RF)
	image.fill(Color(.2,0,0))
	chunk.init_chunk(Vector2i.ZERO,128,Vector3.ZERO,image,0,100)
	var material := StandardMaterial3D.new()
	chunk.update_lod_now(1,material)
	var old: Node3D = chunk.mesh_instance.get_parent()
	chunk.update_lod(0,material)
	assert(chunk.is_building() and old.visible and chunk.current_lod==1)
	# 이동 중 목표가 바뀌었다 되돌아와도 마지막 목표를 따른다.
	chunk.update_lod(2,material)
	chunk.update_lod(0,material)
	await _finish(chunk,material)
	assert(chunk.current_lod==0 and not old.visible)
	assert(chunk.collision_shape and not chunk.collision_shape.disabled)
	assert(chunk.collision_shape.shape.map_width==17)
	chunk.update_lod(1,material)
	assert(chunk.current_lod==1 and old.visible and chunk.collision_shape.disabled)
	chunk.update_lod(2,material)
	chunk.update_lod(1,material)
	await _finish(chunk,material)
	assert(chunk.current_lod==1 and old.visible and not chunk.is_building())
	chunk.update_lod(0,material)
	assert(not chunk.collision_shape.disabled and chunk.get_render_meshes().size()==1)
	chunk.queue_free()
	await process_frame
	assert(Chunk._active_builds==0)
	report.terrain_state = {"previous_lod_retained":true,"latest_lod_request":true,"collision_and_cache":true,"active_builds":Chunk._active_builds}
	var host := Host.new()
	root.add_child(host)
	var packed := {"campus":[],"major":[],"minor":[],"dense_major":[],"dense_minor":[],"shadow_skipped_buildings":32}
	for i in 32:
		packed.major.append(arrays)
		packed.dense_minor.append(arrays)
	var results := {Vector2i.ZERO:packed}
	# 두 배치가 동시에 진행돼도 청크 키가 덮어써지지 않는다.
	var pending := [null,null]
	_build.call_deferred(host,results,pending,0)
	_build.call_deferred(host,results,pending,1)
	var frames := 0
	while pending[0]==null or pending[1]==null:
		var submitted := Budget.submitted
		await process_frame
		assert(Budget.submitted-submitted<=Budget.MAX_SUBMITS)
		frames += 1
	assert(frames>1 and host._building_chunk_nodes.size()==2)
	var total_meshes := 0
	var shadow_off := 0
	for info in host._building_chunk_nodes.values():
		assert(info.node.visible and info.node.get_meta("shadow_skipped_buildings")==32)
		for group in info.node.get_children():
			for mesh in group.get_children():
				total_meshes += 1
				assert(mesh.get_meta("collision_faces").size()==3)
				if mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shadow_off += 1
	assert(total_meshes==128 and shadow_off==64)
	var collisions := Collisions.new()
	for i in 200:
		collisions.update(host._building_chunk_nodes,Vector2.ZERO)
		await process_frame
		if collisions._jobs.is_empty() and i>2:
			break
	assert(collisions._jobs.is_empty())
	var bodies := 0
	for info in host._building_chunk_nodes.values():
		for group in info.node.get_children():
			for mesh in group.get_children():
				assert(mesh.get_node_or_null("BuildingCollision")!=null)
				bodies += 1
	assert(bodies==128)
	collisions.update(host._building_chunk_nodes,Vector2(10000,10000))
	await process_frame
	for info in host._building_chunk_nodes.values():
		assert(not info.node.has_meta("building_collision"))
	collisions.dispose()
	report.buildings = {"meshes":total_meshes,"shadow_off":shadow_off,"collision_bodies":bodies,"concurrent_batch_keys":2,"frames":frames,"release":true}
	var file := FileAccess.open("res://state_verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("STREAMING_STATE_OK ",JSON.stringify(report))
	quit()

func _finish(chunk: Node3D,material: Material) -> void:
	while chunk.is_building():
		chunk.poll_build(material)
		await process_frame

func _build(host: Node3D,results: Dictionary,pending: Array,index: int) -> void:
	pending[index] = await Buildings.attach_streamed(host,results)
