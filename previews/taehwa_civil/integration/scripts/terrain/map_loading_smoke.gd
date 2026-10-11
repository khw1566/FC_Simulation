extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("MapSelectionService").select_map_by_id("ulsan_metro_80km")
	var service := root.get_node("LoadingManagerService")
	var start := Time.get_ticks_msec()
	service.transition_to_map()
	var generation: int = service._generation
	service.transition_to_map()
	var duplicate_blocked: bool = service._generation == generation
	var frames := 0
	var longest := 0
	var previous := start
	var last_report := start
	while service.is_loading and Time.get_ticks_msec() - start < 240000:
		await process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - previous)
		previous = now
		frames += 1
		if now - last_report > 10000:
			last_report = now
			print("로딩 검사: ", (now - start) / 1000, "초 / frames=", frames, " / max_ms=", longest)
	var passed: bool = not service.is_loading and current_scene != null and current_scene.name == "MainWorld"
	var status := {"passed": passed, "duplicate_request_blocked": duplicate_blocked, "seconds": (Time.get_ticks_msec() - start) / 1000.0, "frames_during_load": frames, "longest_frame_ms": longest, "static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
	if passed:
		var manager := current_scene.get_node("BuildingRoadManager")
		var stream: Node = null
		for child in manager.get_children():
			if child.get_script() == preload("res://scripts/terrain/vector_data_stream.gd"):
				stream = child
		if stream != null:
			var initial: int = stream.loaded.size() + stream.roads_loaded.size()
			var sample_start := Time.get_ticks_usec()
			var sample_previous := sample_start
			var sample_frames := 0
			var sample_peak := 0
			while Time.get_ticks_usec() - sample_start < 3000000:
				await process_frame
				var sample_now := Time.get_ticks_usec()
				sample_peak = maxi(sample_peak, sample_now - sample_previous)
				sample_previous = sample_now
				sample_frames += 1
			status["stationary_fps"] = sample_frames * 1000000.0 / (sample_previous - sample_start)
			status["stationary_peak_ms"] = sample_peak / 1000.0
			status["stationary_stream_stable"] = initial == stream.loaded.size() + stream.roads_loaded.size()
			status["resident_batches"] = initial
			status["total_batches"] = stream.entries.size()
			passed = passed and status.stationary_stream_stable and initial < stream.entries.size()
		var hud := current_scene.get_node("PerformanceHUD")
		hud.set_hud_visible(false)
		status["fps_disabled_stops_processing"] = not hud.is_processing()
		hud.set_hud_visible(true)
		await create_timer(0.6).timeout
		status["fps_label_updated"] = "FPS" in hud._label.text
		passed = passed and status.fps_disabled_stops_processing and status.fps_label_updated
	service._return_to_menu()
	for i in range(8):
		await process_frame
	status["menu_returned"] = current_scene != null and current_scene.scene_file_path == service.MENU_PATH
	service.transition_to_map()
	await process_frame
	service._return_to_menu()
	while is_instance_valid(service._image_job):
		await process_frame
	for i in range(8):
		await process_frame
	status["cancel_recovered"] = not service.is_loading and not root.disable_3d and current_scene.scene_file_path == service.MENU_PATH
	status.passed = passed and duplicate_blocked and status.menu_returned and status.cancel_recovered
	var file := FileAccess.open("res://../results/map_loading_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(status, "  "))
	print(JSON.stringify(status))
	quit(0 if passed else 1)
