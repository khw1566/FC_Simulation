extends SceneTree

const Horizon = preload("res://scripts/terrain/horizon_terrain_manager.gd")
const Sampler = preload("res://scripts/terrain/horizon_height_sampler.gd")
const Altitude = preload("res://scripts/services/altitude_atmosphere_controller.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var source: String = arguments[0]
	var output: String = arguments[1]
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+"/assets/generated/horizon/terrain.json"))
	catalog.regional.height_file = source+"/assets/generated/horizon/regional_height.f32"
	catalog.regional.height_texture = source+"/assets/generated/horizon/regional_height_rgb.png"
	var sampler := Sampler.new()
	sampler.configure(catalog,"ulsan_metro_80km")
	var probes := {}
	for item in [["쓰시마",129.3,34.4],["큐슈",130.9,33.5],["혼슈",131.7,34.4],["대한해협",130.0,35.0]]:
		var point := _world(catalog.maps.ulsan_metro_80km,item[1],item[2])
		var h: float = sampler.height(point.x,point.y)
		probes[item[0]] = {"world_x":point.x,"world_z":point.y,"elevation":h}
		if item[0] != "대한해협" and h <= 10.0:
			failures.append("육지 표본: "+item[0])
		if item[0] == "대한해협" and h >= 0.0:
			failures.append("해수면 표본")
	root.size = Vector2i(1280,720)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = Sky.new()
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/night_sky.gdshader")
	sky.set_shader_parameter("sun_direction",Vector3(0.3,0.65,-0.7).normalized())
	environment.environment.sky.sky_material = sky
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.70,0.78,0.90)
	environment.environment.ambient_light_energy = 0.45
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-30,0)
	root.add_child(sun)
	var horizon := Horizon.new()
	horizon.auto_initialize = false
	root.add_child(horizon)
	# 원경 작업 스레드도 별도 프리뷰 프로젝트 안에서 확인한다.
	DirAccess.make_dir_recursive_absolute("res://assets/generated/horizon")
	var isolated_catalog := FileAccess.open(Horizon.CATALOG,FileAccess.WRITE)
	isolated_catalog.store_string(JSON.stringify(catalog))
	isolated_catalog.close()
	var worker := Thread.new()
	var start := Time.get_ticks_msec()
	worker.start(horizon._generate.bind("ulsan_metro_80km",PackedFloat32Array()))
	var responsive_frames := 0
	while worker.is_alive():
		await process_frame
		responsive_frames += 1
	var generated: Dictionary = worker.wait_to_finish()
	var build_ms := Time.get_ticks_msec()-start
	var instance: MeshInstance3D = horizon._install(generated.catalog,generated.map_id,generated.arrays)
	# 중앙 구멍에는 로컬 높이 표본만 사용한다. 게임의 청크·충돌·벡터 객체는 로드하지 않는다.
	var central := MeshInstance3D.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(64):
		for x in range(64):
			for offset in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
				var p: Vector2 = (Vector2(x,z)+offset)/64.0*80000.0-Vector2(40000,40000)
				var height: float = sampler.local_height(p.x,p.y)
				surface.set_color(Color(maxf(height,0.0)/10000.0,0,0))
				surface.add_vertex(Vector3(p.x,maxf(height,0.0),p.y))
	surface.generate_normals()
	central.mesh = surface.commit()
	central.material_override = instance.material_override
	root.add_child(central)
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var tilted := 0
	for normal in arrays[Mesh.ARRAY_NORMAL]:
		if normal.y < 0.999:
			tilted += 1
	if tilted < 1000:
		failures.append("지형 경사 법선")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.near = 2.0
	camera.far = 1600000.0
	camera.fov = 72.0
	camera.position = Vector3(0,50000,0)
	camera.look_at(Vector3(45000,-2000,150000))
	var controller := Altitude.new()
	controller.player_camera = camera
	controller.world_environment = environment
	root.add_child(controller)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/261004_HighAltitude50km.png")
	var file := FileAccess.open(output+"/261004_HighAltitudeValidation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"probes":probes,"triangles":arrays[Mesh.ARRAY_INDEX].size()/3,
		"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"tilted_normals":tilted,"altitude_m":50000,
		"worker_build_ms":build_ms,"responsive_frames_during_build":responsive_frames,
		"scope":"독립 원경만 검증, 전체 게임·건물·도로 미실행"},"\t"))
	file.close()
	quit(0 if failures.is_empty() else 1)

func _world(map: Dictionary,lon: float,lat: float) -> Vector2:
	return Vector2((lon-map.bbox.west)/(map.bbox.east-map.bbox.west)-0.5,
		(map.bbox.north-lat)/(map.bbox.north-map.bbox.south)-0.5)*float(map.world_size_meters)
