extends Node
class_name VectorDataStream

const BatchAssembler = preload("res://scripts/terrain/building_batch_assembler.gd")
const RoadBatchBuilder = preload("res://scripts/terrain/road_batch_builder.gd")

var host: Node3D
var folder := ""
var entries: Array = []
## 파일명 -> {"entry", "node"}
var loaded: Dictionary = {}
## 파일명 -> {"entry", "record"}. record가 비어 있으면(방파제) 해제하지 않는다.
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
var _budget_frame := -1
var _replan_requested := false
var _last_refresh := Vector2(INF, INF)
# 작업 스레드에서 동시에 준비 중인 배치. 같은 배치를 중복 요청하지 않도록 파일명으로 기록한다.
var _pending: Dictionary = {}
var _running := 0
var _done := 0

## 이번 프레임의 메인 스레드 작업 예산을 다 썼으면 다음 프레임으로 넘긴다.
func yield_if_budget_used() -> void:
	_sync_budget_frame()
	var budget: int = FRAME_BUDGET_USEC if host.load_complete else 8000
	if Time.get_ticks_usec() - _frame_started < budget:
		return
	await get_tree().process_frame
	_sync_budget_frame()

func _sync_budget_frame() -> void:
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_frame_started = Time.get_ticks_usec()

## 동시에 준비할 배치 수. 로딩 화면에서는 코어를 더 써서 첫 화면을 빨리 채운다.
func _parallel_limit() -> int:
	var cores := OS.get_processor_count()
	if host.load_complete:
		return clampi(cores / 2 - 1, 1, 4)
	return clampi(cores - 1, 1, 8)

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
	await _refresh(host.initial_load_radius)
	if not is_inside_tree():
		return
	if error.is_empty():
		_last_refresh = Vector2(INF, INF)
		_background.call_deferred()

## 파일 읽기·해시 검증·JSON 해석. 멤버를 바꾸지 않으므로 작업 스레드에서 실행할 수 있다.
static func _parse_batch(base: String, entry: Dictionary) -> Dictionary:
	var path := base.path_join(str(entry.file))
	if not FileAccess.file_exists(path):
		return {"_error": "지도 분할 파일이 없습니다: " + str(entry.file)}
	var text := FileAccess.get_file_as_string(path)
	if text.sha256_text() != str(entry.sha256):
		return {"_error": "지도 분할 파일이 손상됐습니다: " + str(entry.file)}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.get(str(entry.kind)) is Array or parsed[str(entry.kind)].size() != int(entry.count):
		return {"_error": "지도 분할 자료 형식이 잘못됐습니다."}
	return parsed

## 작업 스레드용 배치 준비: 해석 후 도로는 메타데이터 보정과 중복 판정 키 계산까지 마친다.
static func _prepare_batch(base: String, entry: Dictionary, road_metadata: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var parsed := _parse_batch(base, entry)
	if not parsed.has("_error") and str(entry.kind) == "roads":
		RoadBatchBuilder.apply_metadata(parsed.roads, road_metadata)
		RoadBatchBuilder.attach_geometry_keys(parsed.roads)
	parsed["_usec"] = Time.get_ticks_usec() - started
	return parsed

## 작업 스레드에서 실행하고 끝날 때까지 프레임을 넘기며 기다린다.
func _run_task(job: Callable) -> Variant:
	var holder := [null]
	var task := WorkerThreadPool.add_task(func(): holder[0] = job.call(), false, "지도 배치 준비")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return holder[0]

func _alive() -> bool:
	return is_inside_tree() and is_instance_valid(host)

## 배치 하나를 준비한다. 읽기·해석·메시 계산은 작업 스레드, 대체 판정과 노드 생성만 메인 스레드에서 한다.
func _stream_entry(entry: Dictionary) -> void:
	_running += 1
	_pending[entry.file] = true
	await _build_entry(entry)
	_pending.erase(entry.file)
	_running -= 1
	_done += 1

func _build_entry(entry: Dictionary) -> void:
	var base := folder
	var kind := str(entry.kind)
	var metadata: Dictionary = host.road_metadata_entries() if kind == "roads" else {}
	var parsed: Dictionary = await _run_task(func(): return _prepare_batch(base, entry, metadata))
	if not _alive():
		return
	if parsed.has("_error"):
		error = parsed._error
		return
	read_parse_usec += int(parsed.get("_usec", 0))
	if kind == "buildings":
		var build_started := Time.get_ticks_usec()
		var chunks := BatchAssembler.group(host, parsed.buildings)
		var sampler: Callable = host.threaded_ground_sampler()
		var results: Dictionary = await _run_task(func(): return BatchAssembler.compute(chunks, sampler))
		if not _alive():
			return
		# 여러 배치가 같은 프레임에 끝나도 노드 생성은 프레임 예산 안에서 나눠 붙인다.
		await yield_if_budget_used()
		if not _alive():
			return
		var node: Node3D = await BatchAssembler.attach_streamed(host,results)
		if not _alive():
			return
		loaded[entry.file] = {"entry":entry,"node":node}
		resident_buildings += int(entry.count)
		building_build_submit_usec += Time.get_ticks_usec() - build_started
	elif kind == "roads":
		await yield_if_budget_used()
		if not _alive():
			return
		var record: Dictionary = await host._render_roads_and_tunnels_batched(parsed.roads, true, str(entry.file))
		if not _alive():
			return
		roads_loaded[entry.file] = {"entry": entry, "record": record}
	else:
		await yield_if_budget_used()
		if not _alive():
			return
		host._render_breakwaters(parsed.get("breakwaters", []))
		roads_loaded[entry.file] = {"entry": entry, "record": {}}

func _position() -> Vector2:
	if is_instance_valid(host.player_node):
		return Vector2(host.player_node.global_position.x, host.player_node.global_position.z)
	return Vector2.ZERO

func _distance(entry: Dictionary, point: Vector2) -> float:
	return Vector2(entry.center[0], entry.center[1]).distance_squared_to(point)

func _report(total: int) -> void:
	host.load_status = "주변 도로·건물 준비 %d / %d" % [_done, total]
	if not host.load_complete:
		host.load_progress = float(_done) / maxf(1, total)

func _refresh(radius: float) -> void:
	_replan_requested = false
	var point := _position()
	# 이탈한 건물·도로는 여유 반경 밖에서 해제해 경계 왕복 시 재생성을 줄인다.
	var retention: float = host.max_view_distance + (2000.0 if host.buildings_roads_path.contains("buildings_20261003") else 4500.0)
	for key in loaded.keys():
		var record: Dictionary = loaded[key]
		if _distance(record.entry, point) > pow(retention + float(record.entry.get("radius", 1100)), 2):
			host.release_building_batch(record.node)
			resident_buildings -= int(record.entry.count)
			loaded.erase(key)
	for key in roads_loaded.keys():
		var road: Dictionary = roads_loaded[key]
		if road.record.is_empty():
			continue
		if _distance(road.entry, point) > pow(retention + float(road.entry.get("radius", 1100)), 2):
			host.release_road_batch(road.record)
			roads_loaded.erase(key)
	var candidates: Array = []
	for entry in entries:
		if loaded.has(entry.file) or roads_loaded.has(entry.file) or _pending.has(entry.file):
			continue
		if radius < 0.0 or _distance(entry, point) <= pow(radius + float(entry.get("radius", 1100)), 2):
			candidates.append(entry)
	candidates.sort_custom(func(a, b): return _distance(a, point) < _distance(b, point))
	_done = 0
	var cursor := 0
	while cursor < candidates.size():
		if not _alive():
			return
		if not error.is_empty():
			break
		# 이동 전 위치의 대기열을 끝까지 소진하지 않고 새 위치에서 다시 정렬한다.
		if _position().distance_squared_to(point) >= REPRIORITIZE_DISTANCE * REPRIORITIZE_DISTANCE:
			_replan_requested = true
			break
		if _running < _parallel_limit():
			_stream_entry(candidates[cursor])
			cursor += 1
			continue
		_report(candidates.size())
		await get_tree().process_frame
	# 이미 시작한 배치는 끝까지 기다려 부분 적용 상태를 남기지 않는다.
	while _running > 0:
		_report(candidates.size())
		await get_tree().process_frame
		if not _alive():
			return
	if not error.is_empty():
		host.load_error = error
		return
	_report(candidates.size())
	if not _replan_requested:
		_last_refresh = point

func _background() -> void:
	while is_inside_tree() and error.is_empty():
		if _replan_requested:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
		var loader := get_node_or_null("/root/LoadingManagerService")
		if not host.load_complete or (loader and loader.is_loading):
			continue
		if not _replan_requested and _position().distance_squared_to(_last_refresh) < REPRIORITIZE_DISTANCE * REPRIORITIZE_DISTANCE:
			continue
		await _refresh(host.max_view_distance + host.prefetch_distance)
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
	for i in range(0, data.get("roads", []).size(), 64):
		if not is_inside_tree():
			return
		await host._render_roads_and_tunnels_batched(data.roads.slice(i, i + 64), true)
		if not is_inside_tree():
			return
	if is_inside_tree():
		host._render_breakwaters(data.get("breakwaters", []))

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
