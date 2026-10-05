extends SceneTree

const Atmosphere = preload("res://scripts/models/atmosphere_scattering_model.gd")
const AltitudeController = preload("res://scripts/services/altitude_atmosphere_controller.gd")
const Horizon = preload("res://scripts/terrain/horizon_terrain_manager.gd")
const Sampler = preload("res://scripts/terrain/horizon_height_sampler.gd")
const Builder = preload("res://scripts/terrain/horizon_ring_builder.gd")
const Weather = preload("res://scripts/weather/weather_manager.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Horizon.CATALOG))
	var previous := 2.0
	for altitude in [0.0,1000.0,10000.0,20000.0,40000.0,80000.0]:
		var density: float = Atmosphere.density(altitude)
		_check(density < previous, "밀도 감소")
		previous = density
		var column: float = Atmosphere.column(altitude,1.0)
		_check(column >= 0.0 and column <= 8100.0, "유효 광학 경로")
	_check(Atmosphere.column(40000.0,1.0) < Atmosphere.column(0.0,1.0)*0.01, "40km 천정 산란 감소")
	_check(Atmosphere.column(40000.0,0.0) > Atmosphere.column(40000.0,1.0)*10, "수평선 대기 띠")
	for map_id in catalog.maps:
		var sampler := Sampler.new()
		sampler.configure(catalog,map_id)
		var mesh := Builder.new().build(sampler,catalog.settings)
		var arrays := mesh.surface_get_arrays(0)
		_check(arrays[Mesh.ARRAY_INDEX].size()/3 <= 600000, "광역 원경 삼각형 예산 상한")
		var half: float = sampler.map.world_size_meters*0.5-32.1
		for point in arrays[Mesh.ARRAY_VERTEX]:
			_check(maxf(absf(point.x),absf(point.z)) >= half, "상세 지형 중앙 비움")
			_check(is_finite(point.y), "원경 표고 유효")
		mesh = null
	root.size = Vector2i(960,540)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = Sky.new()
	environment.environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/night_sky.gdshader")
	material.set_shader_parameter("sun_direction",Vector3(0.3,0.65,-0.7).normalized())
	environment.environment.sky.sky_material = material
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.rotation_degrees.x = 15
	var controller := AltitudeController.new()
	controller.player_camera = camera
	controller.world_environment = environment
	root.add_child(controller)
	var weather := Weather.new()
	weather.player_node = camera
	weather.world_environment = environment
	var previous_luminance := 2.0
	for altitude in [0.0,10000.0,20000.0,40000.0]:
		camera.position.y = altitude
		controller._process(0)
		weather._apply_altitude_adjusted_fog()
		_check(is_equal_approx(environment.environment.fog_density,0.000028*Atmosphere.density(altitude)), "날씨 안개 밀도 일치")
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var pixel := image.get_pixel(80,80)
		var luminance := (pixel.r+pixel.g+pixel.b)/3.0
		_check(luminance < previous_luminance, "실제 렌더 천정 밝기 감소")
		previous_luminance = luminance
		if altitude == 0.0:
			_check(pixel.b > pixel.r, "지표 푸른 산란")
		if altitude == 40000.0:
			_check(luminance < 0.04, "40km 검은 하늘")
		image.save_png("res://../results/261004_Atmosphere_%dm.png" % int(altitude))
	var horizon := Horizon.new()
	horizon.auto_initialize = false
	root.add_child(horizon)
	var instance: MeshInstance3D = horizon.build(catalog,"ulsan_metro_80km")
	_check(instance.get_child_count() == 0, "충돌 및 상세 객체 미생성")
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-25,0)
	root.add_child(light)
	camera.position = Vector3(80000,110000,120000)
	camera.look_at(Vector3.ZERO)
	controller._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../results/261004_HorizonTerrain.png")
	var file := FileAccess.open("res://../results/261004_AtmosphereHorizonValidation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"triangles_per_map":catalog.settings.edge_segments*4*catalog.settings.radial_rings*2,"atlas_bytes":FileAccess.get_file_as_bytes(Horizon.CATALOG).size()},"  "))
	file.close()
	weather.free()
	print("ATMOSPHERE_HORIZON checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
