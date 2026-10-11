extends RefCounted
class_name BuildingCollisionStream

## 플레이어 주변 건물 청크에만 충돌체를 만들고 멀어지면 해제한다.
## 충돌 형상은 메시 생성 때 보관한 삼각형 정점으로 작업 스레드에서 만든다.
## 렌더링 메시에서 형상을 만들면(create_trimesh_shape) GPU 버퍼를 다시 읽어 메인 스레드가 멈춘다.
const COLLISION_META := "building_collision"
const FACES_META := "collision_faces"
const Budget = preload("res://scripts/terrain/stream_frame_budget.gd")
# 1,500m 건물 청크 기준으로 플레이어 주변 최소 약 1.2km를 덮는다.
var create_radius := 2250.0
var release_radius := 2750.0
# 지면 위 이 높이보다 높이 날 때는 새 충돌체를 만들지 않는다. 이미 만든 충돌체는 거리 기준으로만 해제한다.
var max_clearance := 600.0
var max_running_tasks := 2
var _jobs: Array = []
var _serial := 0

## chunks: { key: {"node": Node3D, "center_2d": Vector2} }
func update(chunks: Dictionary, player_2d: Vector2, clearance: float = 0.0) -> void:
	_collect_finished()
	var pending: Array = []
	for info in chunks.values():
		var node: Node3D = info.get("node")
		if not is_instance_valid(node):
			continue
		var distance := player_2d.distance_to(info.get("center_2d", Vector2.ZERO))
		var has_collision := node.has_meta(COLLISION_META)
		if has_collision and distance > release_radius:
			_release(node)
		elif not has_collision and distance <= create_radius and clearance <= max_clearance:
			pending.append({"node": node, "distance": distance})
	if _jobs.size() >= max_running_tasks or pending.is_empty():
		return
	pending.sort_custom(func(a, b): return a.distance < b.distance)
	for index in mini(max_running_tasks - _jobs.size(), pending.size()):
		_start(pending[index].node)

## 남은 작업을 모두 회수한다. 관리자가 트리에서 빠질 때 호출한다.
func dispose() -> void:
	for job in _jobs:
		if not job.get("collected",false):
			WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()

func _start(chunk_node: Node3D) -> void:
	_serial += 1
	chunk_node.set_meta(COLLISION_META, _serial)
	var targets: Array = []
	var faces: Array = []
	for container in chunk_node.get_children():
		for child in container.get_children():
			if child is MeshInstance3D and child.has_meta(FACES_META):
				var vertices: PackedVector3Array = child.get_meta(FACES_META)
				if vertices.size() >= 3:
					targets.append(child)
					faces.append(vertices)
	if targets.is_empty():
		return
	var shapes: Array = []
	var build := func() -> void:
		for vertices in faces:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(vertices)
			shapes.append(shape)
	var task := WorkerThreadPool.add_task(build, false, "건물 충돌 형상")
	_jobs.append({"task": task, "node": chunk_node, "serial": _serial, "targets": targets, "shapes": shapes})

## 끝난 작업의 형상을 메인 스레드에서 붙인다. 그 사이 해제·재요청된 청크의 결과는 버린다.
func _collect_finished() -> void:
	var running: Array = []
	for job in _jobs:
		if not job.get("collected",false) and not WorkerThreadPool.is_task_completed(job.task):
			running.append(job)
			continue
		if not job.get("collected",false):
			WorkerThreadPool.wait_for_task_completion(job.task)
			job.collected = true
			job.cursor = 0
		var node = job.node
		if not is_instance_valid(node) or node.get_meta(COLLISION_META, -1) != job.serial:
			continue
		while job.cursor<job.targets.size():
			if not Budget.can_submit():
				running.append(job)
				break
			var index: int = job.cursor
			job.cursor += 1
			var target = job.targets[index]
			if not is_instance_valid(target):
				continue
			var started := Time.get_ticks_usec()
			var body := StaticBody3D.new()
			body.name = "BuildingCollision"
			var shape := CollisionShape3D.new()
			shape.shape = job.shapes[index]
			body.add_child(shape)
			target.add_child(body)
			Budget.record(started)
	_jobs = running

func _release(chunk_node: Node3D) -> void:
	chunk_node.remove_meta(COLLISION_META)
	for container in chunk_node.get_children():
		for child in container.get_children():
			var body := child.get_node_or_null("BuildingCollision")
			if body:
				body.queue_free()
