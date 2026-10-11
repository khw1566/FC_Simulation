extends SceneTree
## 큐슈 M 지도 연결, 입력, 미니맵 및 좌표 이동을 실제 HUD에서 확인한다.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.get_node("MapSelectionService").select_map_by_id("kyushu_wide")
	var view = load("res://scenes/map_hud.tscn").instantiate()
	root.add_child(view)
	await process_frame
	var controller = load("res://scripts/controllers/map_hud_controller.gd").new()
	controller.map_hud_view = view
	root.add_child(controller)
	var event := InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	controller._unhandled_input(event)
	await process_frame
	var selected = root.get_node("MapSelectionService").selected_map
	var checks := {"M키_전체지도": view.is_fullscreen_open and view.fullscreen_map_modal.visible,
		"큐슈_전용_경로": selected.tactical_map_path == "res://assets/maps/kyushu_wide/kyushu_tactical_map.png",
		"미니맵_동일텍스처": view.minimap_tex.texture == view.fs_map_tex.texture,
		"지도_해상도": view.fs_map_tex.texture.get_size() == Vector2(2048, 2048),
		"원본_행정경계_동일좌표": selected.districts_path == "res://assets/maps/kanmon_straits/real_districts.json", "월드좌표_범위": view.world_size == 28000}
	view._apply_zoom_at_point(view.fs_map_tex.size / 2, 1.2)
	checks["확대"] = is_equal_approx(view._zoom_level, 1.2)
	view.reset_map_view()
	var travel: Array = []
	view.travel_requested.connect(func(point): travel.append(point))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view._map_offset + view.fs_map_tex.size / 2
	view.handle_fullscreen_gui_input(click)
	checks["지도중앙_이동좌표"] = travel.size() == 1 and travel[0].length() < 0.01
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../results/261003_kyushu_M_map.png")
	var passed := not checks.values().has(false)
	var file := FileAccess.open("res://../results/261003_kyushu_map_hud_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks}, "  "))
	print(JSON.stringify(checks))
	quit(0 if passed else 1)

