extends Node

const LOADING_SCREEN_SCENE := preload("res://scenes/ui/loading_screen.tscn")
const MAIN_WORLD_PATH := "res://scenes/main_world.tscn"
const MENU_PATH := "res://scenes/ui/map_selection_menu.tscn"
var _loading_canvas: CanvasLayer
var _loading_view: Control
var is_loading := false
var _generation := 0
var _started_ms := 0
var _last_progress := 0.0
var image_cache: Dictionary = {}
var _image_job: Node
const ImagePreloader = preload("res://scripts/services/map_image_preloader.gd")

func transition_to_map() -> void:
	if is_loading:
		return
	var service := get_node_or_null("/root/MapSelectionService")
	if service == null or service.selected_map == null:
		return
	is_loading = true
	get_tree().root.disable_3d = true
	_generation += 1
	_started_ms = Time.get_ticks_msec()
	_last_progress = 0
	_loading_canvas = CanvasLayer.new()
	_loading_canvas.layer = 100
	get_tree().root.add_child(_loading_canvas)
	_loading_view = LOADING_SCREEN_SCENE.instantiate()
	_loading_canvas.add_child(_loading_view)
	_loading_view.setup_view(service.selected_map.get_localized_name(service.current_language), null, {}, service.selected_map)
	var cancel := Button.new()
	cancel.text = "지도 선택으로 돌아가기"
	cancel.position = Vector2(24, 24)
	cancel.pressed.connect(_return_to_menu)
	_loading_view.add_child(cancel)
	_execute_load_sequence(_generation)

func _progress(value: float, message: String) -> void:
	_last_progress = maxf(_last_progress, value)
	if is_instance_valid(_loading_view):
		_loading_view.set_progress(_last_progress, message)

func _execute_load_sequence(generation: int) -> void:
	await get_tree().process_frame
	_progress(3, "지도 실행 준비")
	var config = get_node("/root/MapSelectionService").selected_map
	while is_instance_valid(_image_job):
		await get_tree().process_frame
		if generation != _generation:
			return
	var images := ImagePreloader.new()
	_image_job = images
	add_child(images)
	var prepared := await images.prepare([config.heightmap_path, config.watermask_path, config.sea_mask_path, config.lake_mask_path, config.splatmap_path, config.tactical_map_path])
	images.queue_free()
	_image_job = null
	if generation != _generation:
		return
	image_cache = prepared
	if not image_cache.has(config.heightmap_path):
		_fail("지도 높이맵을 읽지 못했습니다.")
		return
	var error := ResourceLoader.load_threaded_request(MAIN_WORLD_PATH)
	if error != OK:
		_fail("월드 파일 읽기를 시작하지 못했습니다.")
		return
	while true:
		if generation != _generation:
			return
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(MAIN_WORLD_PATH, progress)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail("월드 파일을 읽지 못했습니다.")
			return
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if _timed_out():
			return
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(MAIN_WORLD_PATH) as PackedScene
	if packed == null or get_tree().change_scene_to_packed(packed) != OK:
		_fail("월드 화면을 만들지 못했습니다.")
		return
	await get_tree().process_frame
	while generation == _generation:
		var world := get_tree().current_scene
		if world != null and world.scene_file_path == MAIN_WORLD_PATH:
			var player := world.get_node_or_null("Player")
			if player != null:
				player.process_mode = Node.PROCESS_MODE_DISABLED
			var terrain := world.get_node_or_null("TerrainManager")
			var vectors := world.get_node_or_null("BuildingRoadManager")
			if terrain == null or vectors == null:
				_fail("지도 구성 요소가 누락됐습니다.")
				return
			if not terrain.load_error.is_empty() or not vectors.load_error.is_empty():
				_fail(terrain.load_error if not terrain.load_error.is_empty() else vectors.load_error)
				return
			if not terrain.load_complete:
				_progress(10 + 40.0 * terrain.active_chunks.size() / maxf(1, terrain.grid_chunks_x * terrain.grid_chunks_y), terrain.load_status)
			else:
				_progress(55 + 43 * vectors.load_progress, vectors.load_status)
			if terrain.load_complete and vectors.load_complete:
				get_tree().root.disable_3d = false
				if player != null:
					player.process_mode = Node.PROCESS_MODE_INHERIT
				_progress(100, "지도 준비 완료")
				_loading_view.fade_out_and_finish(func():
					if generation == _generation:
						_finish())
				return
		if _timed_out():
			return
		await get_tree().process_frame

func _timed_out() -> bool:
	if Time.get_ticks_msec() - _started_ms > 240000:
		_fail("지도 준비 시간이 초과됐습니다. 지도 선택으로 돌아가 다시 시도하세요.")
		return true
	return false

func _fail(message: String) -> void:
	push_error(message)
	_progress(_last_progress, "불러오기 중단: " + message)
	# 실패 화면은 유지해 원인을 확인하고 선택 화면으로 돌아갈 수 있게 한다.

func _return_to_menu() -> void:
	if is_instance_valid(_image_job):
		_image_job.cancel()
	image_cache.clear()
	get_tree().root.disable_3d = false
	_generation += 1
	is_loading = false
	if is_instance_valid(_loading_canvas):
		_loading_canvas.queue_free()
	_loading_canvas = null
	_loading_view = null
	get_tree().change_scene_to_file(MENU_PATH)

func _finish() -> void:
	image_cache.clear()
	is_loading = false
	if is_instance_valid(_loading_canvas):
		_loading_canvas.queue_free()
	_loading_canvas = null
	_loading_view = null
