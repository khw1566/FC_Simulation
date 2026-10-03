extends Node
class_name VectorDataStream

var host: Node3D
var folder := ""
var entries: Array = []
var loaded: Dictionary = {}
var roads_loaded: Dictionary = {}
var resident_buildings := 0
var error := ""
var worker: Thread
const FRAME_BUDGET_USEC := 2000
var all_regions_ready := false
var read_parse_usec := 0
var building_build_submit_usec := 0
const REPRIORITIZE_DISTANCE := 250.0
var _frame_started := 0
var _replan_requested := false

func yield_if_budget_used() -> void:
	var budget: int = FRAME_BUDGET_USEC if host.load_complete else 8000
	if Time.get_ticks_usec() - _frame_started < budget:
		return
	await get_tree().process_frame
	_frame_started = Time.get_ticks_usec()

func run(manager: Node3D, source: String) -> void:
	host = manager
	folder = source.get_base_dir().path_join("vector_stream")
	var index_path := folder.path_join("index.json")
	if not FileAccess.file_exists(index_path):
		await _legacy(source)
		return
	var index = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	var source_file := FileAccess.open(source, FileAccess.READ)
	if not index is Dictionary or source_file == null:
		error = "지도 분할 인덱스를 읽을 수 없습니다."
		return
	if int(index.get("source_size", -1)) != source_file.get_length() or int(index.get("source_modified", -1)) != FileAccess.get_modified_time(source):
		error = "지도 자료가 변경되어 분할 캐시 재생성이 필요합니다."
		return
	source_file.close()
	entries = index.get("batches", [])
	_frame_started = Time.get_ticks_usec()
	await _refresh(host.max_view_distance + 1500.0)
	if not is_inside_tree():
		return
	if error.is_empty():
		_background.call_deferred()

func _read_batch(entry: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var path := folder.path_join(str(entry.file))
	if not FileAccess.file_exists(path):
		error = "지도 분할 파일이 없습니다: " + str(entry.file)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.sha256_text() != str(entry.sha256):
		error = "지도 분할 파일이 손상됐습니다: " + str(entry.file)
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.get(str(entry.kind)) is Array or parsed[str(entry.kind)].size() != int(entry.count):
		error = "지도 분할 자료 형식이 잘못됐습니다."
		return {}
	read_parse_usec += Time.get_ticks_usec() - started
	return parsed

func _position() -> Vector2:
	if is_instance_valid(host.player_node):
		return Vector2(host.player_node.global_position.x, host.player_node.global_position.z)
	return Vector2.ZERO

func _distance(entry: Dictionary, point: Vector2) -> float:
	return Vector2(entry.center[0], entry.center[1]).distance_squared_to(point)

func _refresh(radius: float) -> void:
	_replan_requested = false
	var point := _position()
	# 이탈한 건물은 여유 반경 밖에서 해제해 경계 왕복 시 재생성을 줄인다.
	var retention: float = host.max_view_distance + (2000.0 if host.buildings_roads_path.contains("buildings_20261003") else 4500.0)
	for key in loaded.keys():
		var record: Dictionary = loaded[key]
		if _distance(record.entry, point) > pow(retention + float(record.entry.get("radius", 1100)), 2):
			host.release_building_batch(record.node)
			resident_buildings -= int(record.entry.count)
			loaded.erase(key)
	var candidates: Array = []
	for entry in entries:
		if not loaded.has(entry.file) and not roads_loaded.has(entry.file) and (radius < 0.0 or _distance(entry, point) <= pow(radius + float(entry.get("radius", 1100)), 2)):
			candidates.append(entry)
	candidates.sort_custom(func(a, b): return _distance(a, point) < _distance(b, point))
	var count := 0
	for entry in candidates:
		if not is_inside_tree() or not is_instance_valid(host):
			return
		# 이동 전 위치의 대기열을 끝까지 소진하지 않고 새 위치에서 다시 정렬한다.
		if _position().distance_squared_to(point) >= REPRIORITIZE_DISTANCE * REPRIORITIZE_DISTANCE:
			_replan_requested = true
			return
		if entry.kind != "buildings":
			var extra := _read_batch(entry)
			if not error.is_empty():
				host.load_error = error
				return
			if entry.kind == "roads":
				host._apply_road_metadata(extra.roads)
				await host._render_roads_and_tunnels_batched(extra.roads, yield_if_budget_used)
				if not is_inside_tree():
					return
			else:
				host._render_breakwaters(extra.get("breakwaters", []))
			roads_loaded[entry.file] = true
			count += 1
			host.load_status = "주변 도로·건물 준비 %d / %d" % [count, candidates.size()]
			host.load_progress = float(count) / maxf(1, candidates.size())
			await yield_if_budget_used()
			continue
		var data := _read_batch(entry)
		if not error.is_empty():
			host.load_error = error
			return
		var build_started := Time.get_ticks_usec()
		var container: Node3D = host._render_buildings_batched(data.buildings)
		building_build_submit_usec += Time.get_ticks_usec() - build_started
		loaded[entry.file] = {"entry": entry, "node": container}
		resident_buildings += int(entry.count)
		count += 1
		if not host.load_complete:
			host.load_progress = float(count) / maxf(1, candidates.size())
		host.load_status = "주변 건물 준비 %d / %d" % [count, candidates.size()]
		await yield_if_budget_used()

func _background() -> void:
	while is_inside_tree() and error.is_empty():
		if _replan_requested:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
		_frame_started = Time.get_ticks_usec()
		await _refresh(host.max_view_distance + 1500.0)
		if not is_inside_tree():
			return
		all_regions_ready = loaded.size() + roads_loaded.size() == entries.size()
		host.load_status = "주변 구역 준비 완료 / 상주 건물 %d동" % resident_buildings
	if not error.is_empty():
		push_error(error)

func _legacy(source: String) -> void:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		error = "건물 자료를 읽을 수 없습니다."
		return
	if file.get_length() > 64000000:
		error = "대형 지도 분할 캐시가 없습니다. 캐시 생성 후 다시 실행하세요."
		return
	file.close()
	worker = Thread.new()
	var status := worker.start(func(): return JSON.parse_string(FileAccess.get_file_as_string(source)))
	if status != OK:
		error = "자료 읽기 작업을 시작하지 못했습니다."
		return
	while worker.is_alive():
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var data = worker.wait_to_finish()
	if not data is Dictionary:
		error = "건물 JSON이 손상됐습니다."
		return
	var service := get_node("/root/MapSelectionService")
	host._apply_road_metadata(data.get("roads", []))
	if service.selected_map != null and not service.selected_map.vector_source_meta.is_empty():
		var meta = JSON.parse_string(FileAccess.get_file_as_string(service.selected_map.vector_source_meta))
		if not meta is Dictionary:
			error = "공유 벡터 좌표계 메타데이터를 읽지 못했습니다."
			return
		preload("res://scripts/terrain/vector_map_projection.gd").apply(data, meta, service.selected_map)
	for i in range(0, data.get("buildings", []).size(), 64):
		if not is_inside_tree():
			return
		host._render_buildings_batched(data.buildings.slice(i, i + 64))
		await get_tree().process_frame
	for i in range(0, data.get("roads", []).size(), 8):
		if not is_inside_tree():
			return
		await host._render_roads_and_tunnels_batched(data.roads.slice(i, i + 8))
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if is_inside_tree():
		host._render_breakwaters(data.get("breakwaters", []))

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
