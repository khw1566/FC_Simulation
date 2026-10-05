extends SceneTree

const Route = preload("res://scripts/water/vessel_route.gd")
const Manager = preload("res://scripts/water/vessel_world_manager.gd")
const Preferences = preload("res://scripts/services/user_settings_service.gd")
const Controller = preload("res://scripts/controllers/pause_settings_controller.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Manager.CATALOG))
	for map in catalog.maps.values():
		for entry in map.entries:
			var route = Route.new()
			route.configure(entry, map.sea_level, catalog.settings)
			for i in range(201):
				var t: float = route.duration * float(i) / 200.0
				var pose: Transform3D = route.sample(t)
				_check(is_equal_approx(pose.origin.y, map.sea_level), "수면 기준")
				_check(pose.origin.distance_to(route.sample(t+route.duration).origin) < 0.1, "왕복 주기")
				_check(pose.origin.distance_to(route.sample(t+0.1).origin) <= route.speed*0.1+0.1, "속도 및 연속성")
	var preferences := Preferences.new()
	preferences.settings_file_path = "res://../results/vessel_settings_test.cfg"
	var manager := Manager.new()
	manager.auto_initialize = false
	root.add_child(manager)
	manager.configure(catalog, "ulsan_metro_80km", preferences)
	var expected: int = catalog.maps.ulsan_metro_80km.entries.size()
	_check(manager._models.size() == expected, "울산 배치 카탈로그 전체 모델 로드")
	manager._process(30.0)
	var saved_time: float = manager.elapsed
	var view = load("res://scenes/pause_settings_hud.tscn").instantiate()
	root.add_child(view)
	var controller := Controller.new()
	controller.pause_view = view
	controller.user_settings_service = preferences
	controller._connect_view_signals()
	view.vessels_check.button_pressed = false
	_check(not manager.enabled and manager.get_child_count() == 0 and not manager.is_processing(), "설정 체크박스로 제거 및 정지")
	var restored := Preferences.new()
	restored.settings_file_path = preferences.settings_file_path
	restored.load_settings()
	_check(not restored.vessels_enabled, "설정 저장 및 재로드")
	view.vessels_check.button_pressed = true
	_check(manager.enabled and manager._models.size() == expected and manager.elapsed == saved_time, "재활성화 및 시간 보존")
	view.show_settings_menu()
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../results/261004_VesselSettings.png")
	view.hide()
	manager.set_process(false)
	var seen: Dictionary = {}
	for wake in manager._wakes.values():
		wake.hide()
	for vessel in manager._models.values():
		var kind: String = vessel.get_meta("vessel_type")
		if seen.has(kind):
			vessel.hide()
			continue
		var index := seen.size()
		seen[kind] = true
		vessel.transform = Transform3D(Basis.IDENTITY, Vector3((index % 3 - 1) * 230.0, 0.0, (index / 3) * 240.0 - 120.0))
	_check(seen.size() == 6, "새 선박 6종 모두 사용")
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 650)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.25, 0.31)
	material.roughness = 0.4
	water.material_override = material
	water.position.y = -0.05
	root.add_child(water)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.8
	root.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.19, 0.23)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(420, 680, 650)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 930
	camera.far = 3000
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../results/261004_VesselModels.png")
	var report := {"checks":checks,"failures":failures,"vessels":manager._models.size()}
	var file := FileAccess.open("res://../results/261004_VesselRuntimeValidation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	controller.free()
	preferences.free()
	restored.free()
	manager.free()
	view.free()
	print("VESSEL_CHECK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
