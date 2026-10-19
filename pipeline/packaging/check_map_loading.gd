extends SceneTree

const Validator = preload("res://scripts/terrain/cache_source_validator.gd")
const Quality = preload("res://scripts/models/render_quality_profile.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var selection := root.get_node("MapSelectionService")
	for config in selection.maps:
		var source: String = config.buildings_roads_path
		var index_path := source.get_base_dir().path_join("vector_stream/index.json")
		if not FileAccess.file_exists(index_path):
			continue
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(index_path))
		if not Validator.matches(source, index):
			push_error("패키지 캐시 불일치: " + config.id)
			quit(1)
			return
		# PCK에서 시각 대신 해시가 실제로 검사되는지 확인한다.
		var changed := index.duplicate()
		changed.source_sha256 = "잘못된 해시"
		if Validator.matches(source, changed):
			quit(2)
			return
		print("CACHE_CHECK_OK: ", config.id)
	selection.select_map_by_id("ulsan_metro_80km")
	var settings := root.get_node("UserSettingsService")
	settings.render_quality = "light"
	settings.session_quality = "light"
	var height := Quality.heightmap_path(selection.selected_map)
	# 원본 내용이 실제로 달라진 경량 캐시는 계속 거부하고 원본으로 대체한다.
	print("HEIGHT_PATH: ", height)
	if not "--load-map" in OS.get_cmdline_user_args():
		quit()
		return
	var loader := root.get_node("LoadingManagerService")
	loader.transition_to_map()
	var started := Time.get_ticks_msec()
	var report_at := started
	while loader.is_loading:
		await process_frame
		if Time.get_ticks_msec() - report_at > 10000:
			report_at = Time.get_ticks_msec()
			var terrain := current_scene.get_node_or_null("TerrainManager") if current_scene else null
			print("LOADING_STAGE: ", terrain.load_status if terrain else "장면 준비", " ms=", report_at-started)
		if loader._failed or Time.get_ticks_msec() - started > 180000:
			push_error("지도 준비 실패 또는 180초 초과")
			quit(4)
			return
	print("MAP_LOADING_OK: ", JSON.stringify(loader.stage_timings))
	quit()
