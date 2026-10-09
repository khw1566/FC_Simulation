extends Node3D
## 완성된 PackedScene 3개만 읽는다. 생성기·원본 DEM·철도 JSON에 의존하지 않는다.
const ASSETS := "res://assets/generated/prebaked_rail_test/"
var label: Label
var selector: OptionButton
var start_button: Button
var loaded := false
var smoke := false
var selected_quality := "light"
var capture := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--smoke":
			smoke = true
		if arg=="--capture":
			capture = true
		if arg.begins_with("--quality="):
			selected_quality = arg.trim_prefix("--quality=")
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	ui.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	label = Label.new()
	label.text = "철로 사전 보정 테스트맵 · 울산 실제 지형 약 2km\n품질을 선택하고 시작하세요."
	box.add_child(label)
	selector = OptionButton.new()
	for title in ["경량","표준","고품질"]:
		selector.add_item(title)
	selector.select(maxi(0,["light","standard","high"].find(selected_quality)))
	box.add_child(selector)
	start_button = Button.new()
	start_button.text = "테스트 시작"
	start_button.pressed.connect(_start)
	box.add_child(start_button)
	if smoke:
		_start()

func _start() -> void:
	if loaded:
		return
	loaded = true
	selector.disabled = true
	start_button.disabled = true
	selected_quality = ["light","standard","high"][selector.selected]
	label.text = "사전 생성 자산을 읽는 중..."
	var started := Time.get_ticks_usec()
	var paths := [ASSETS+"terrain_"+selected_quality+".scn",ASSETS+"collision.scn",ASSETS+"railway.scn"]
	for path in paths:
		if ResourceLoader.load_threaded_request(path)!=OK:
			_fail("자산을 읽지 못했습니다: "+path)
			return
	for path in paths:
		while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED:
			_fail("자산 읽기 실패: "+path)
			return
		var packed := ResourceLoader.load_threaded_get(path) as PackedScene
		if packed==null:
			_fail("잘못된 씬 자산: "+path)
			return
		add_child(packed.instantiate())
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS+"catalog.json"))
	_environment()
	var player := CharacterBody3D.new()
	player.name = "TestCamera"
	player.set_script(preload("res://scripts/testing/prebaked_rail_camera.gd"))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.far = 5000.0
	camera.current = true
	player.add_child(camera)
	var collision := CollisionShape3D.new()
	var capsule := SphereShape3D.new()
	capsule.radius = 0.35
	collision.shape = capsule
	player.add_child(collision)
	var at: Array = catalog.camera_position
	player.position = Vector3(at[0],at[1],at[2])
	var target: Array = catalog.camera_target
	player.transform = player.transform.looking_at(Vector3(target[0],target[1],target[2]))
	add_child(player)
	var prepare_ms := (Time.get_ticks_usec()-started)/1000.0
	await get_tree().process_frame
	var ready_ms := (Time.get_ticks_usec()-started)/1000.0
	label.text = "철로 사전 보정 테스트 · %s · 준비 %.1fms\n사전 생성 씬 3개 배치 / 실행 중 지형·노반·터널 생성 0회\n우클릭: 시점 조작 · WASD: 이동 · Q/E: 하강/상승\nShift: 빠르게 · Esc: 마우스 해제 · R: 처음 위치" % [selector.get_item_text(selector.selected),ready_ms]
	selector.hide()
	start_button.hide()
	for view in catalog.get("views",[]):
		var button := Button.new()
		button.text = view.name_ko
		button.pressed.connect(func():
			var eye: Array = view.position
			var aim: Array = view.target
			player.transform = Transform3D(Basis.IDENTITY,Vector3(eye[0],eye[1],eye[2])).looking_at(Vector3(aim[0],aim[1],aim[2]))
			camera.rotation = Vector3.ZERO
		)
		label.get_parent().add_child(button)
	print("PREBAKED_READY ",JSON.stringify({"quality":selected_quality,"asset_read_and_place_ms":prepare_ms,"ready_frame_ms":ready_ms,"packed_scene_reads":3,"runtime_geometry_builds":0}))
	if smoke:
		await get_tree().physics_frame
		await get_tree().physics_frame
		var p: Array = catalog.collision_probe
		var from := Vector3(p[0],p[1]+2.0,p[2])
		var query := PhysicsRayQueryParameters3D.create(from,from+Vector3.DOWN*5.0)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or absf(hit.position.y-(float(p[1])+0.12))>0.2:
			_fail("사전 생성 궤도 충돌 높이 검증 실패")
			return
		print("PREBAKED_COLLISION_OK")
		if capture:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://capture.png")
		get_tree().quit()

func _environment() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.16,0.16,0.16)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)

func _fail(message: String) -> void:
	label.text = message
	push_error(message)
	if smoke:
		get_tree().quit(1)
