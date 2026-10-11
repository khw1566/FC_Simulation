extends SceneTree

const Placement = preload("res://scripts/terrain/pedestrian_bridge_placement.gd")
const Config = preload("res://scripts/models/map_config_model.gd")
const TerrainFixture = preload("res://scripts/core/pedestrian_bridge_terrain_fixture.gd")
var failures: Array[String] = []
var records: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var container := Node3D.new()
	root.add_child(container)
	for map_id in ["ulsan_metro_80km", "southeast_mega_140km", "ulsan_uc_west", "kanmon_straits"]:
		var config = Config.create_from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s/map_meta.json" % map_id)))
		var terrain := TerrainFixture.new()
		container.add_child(terrain)
		terrain.configure(config)
		var manager := Placement.new()
		container.add_child(manager)
		manager.setup(config, terrain)
		var expected := 0 if map_id == "kanmon_straits" else (1 if map_id == "ulsan_uc_west" else 2)
		_expect(manager.placed.size() == expected, "지도 범위별 배치 수: " + map_id)
		_expect(not manager.has_node("generic_pedestrian_overpass"), "범용 육교 보관 유지")
		for model in manager.placed:
			var first := "RoadA" if model.name == "seonbawi_bridge" else "BankA"
			var last := "RoadB" if model.name == "seonbawi_bridge" else "BankB"
			var a := model.get_node(first) as Node3D
			var b := model.get_node(last) as Node3D
			var target_a: Vector3 = model.get_meta("bank_a_world")
			var target_b: Vector3 = model.get_meta("bank_b_world")
			_expect(a.global_position.distance_to(target_a) < 0.01, "첫 기준점 위치 및 표고 정렬")
			_expect(b.global_position.distance_to(target_b) < 0.01, "끝 기준점 위치 및 표고 정렬")
			_expect(model.transform.basis.determinant() > 0, "에셋 좌우 반전 없음")
			_expect(_colliders(model) > 0, "기존 에셋 충돌 보존")
			_expect(manager.replaces_road({"osm_id": model.get_meta("source_osm_ids")[0]}), "원본 도로 중복 제거")
			if model.name == "gulhwa_daun_crossing":
				_expect(manager.has_node("gulhwa_daun_crossing_approaches"), "양안 진입로 보존")
			_expect(a.global_position.y >= terrain.get_terrain_elevation(a.global_position.x,a.global_position.z), "보행면 지형 위 배치")
			records.append({"map":map_id,"model":str(model.name),"bank_a":[target_a.x,target_a.y,target_a.z],"bank_b":[target_b.x,target_b.y,target_b.z],"placed_length_m":target_a.distance_to(target_b),"scale_z":model.transform.basis.z.length(),"terrain_clearance_adjustment_m":model.get_meta("terrain_clearance_adjustment_m")})
			if map_id == "ulsan_metro_80km":
				await _render_site(model, terrain, container)
		manager.free()
		terrain.free()
	var result := {"failures":failures,"placements":records,"full_world_loaded":false,"heightmaps_sampled_only":true}
	var file := FileAccess.open("res://../results/261004_PedestrianBridgePlacementValidation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("[교량 배치 검증] 배치=",records.size()," 실패=",failures.size())
	container.free()
	quit(0 if failures.is_empty() else 1)

func _render_site(model: Node3D, terrain: Node3D, container: Node3D) -> void:
	var a: Vector3 = model.get_meta("bank_a_world")
	var b: Vector3 = model.get_meta("bank_b_world")
	var center := (a + b) * 0.5
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 700)
	viewport.world_3d = root.world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = center + Vector3(170,130,190)
	camera.look_at(center)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 260
	camera.far = 1000
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	container.add_child(light)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(-12, 12):
		for z in range(-12, 12):
			var quad: Array[Vector3] = []
			for offset in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]:
				var p := Vector3(center.x+(x+offset.x)*15,0,center.z+(z+offset.y)*15)
				p.y = terrain.get_terrain_elevation(p.x,p.z)
				quad.append(p)
			for index in [0,1,2,0,2,3]:
				st.add_vertex(quad[index])
	st.generate_normals()
	var patch := MeshInstance3D.new()
	patch.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28,0.30,0.27)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	patch.material_override = material
	container.add_child(patch)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://../results/261004_placed_%s.png" % str(model.name))
	patch.free()
	light.free()
	viewport.free()

func _colliders(node: Node) -> int:
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _colliders(child)
	return count

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
