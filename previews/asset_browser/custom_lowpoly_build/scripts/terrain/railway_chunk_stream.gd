extends Node3D
class_name RailwayChunkStream

## 철도 논리 노선과 분리하여 주변 표시 청크만 생성하고 이탈 청크를 해제한다.
const TrackBuilder = preload("res://scripts/terrain/railway_track_builder.gd")
const Formation = preload("res://scripts/terrain/railway_formation_builder.gd")
const Quality = preload("res://scripts/models/render_quality_profile.gd")
var entries: Array[Dictionary] = []
var active: Dictionary = {}
var _player: Node3D
var _terrain: Node3D
var _quality: Dictionary
var _busy := false
var _timer := 0.0
var _last_position := Vector3(INF, INF, INF)
const DETAIL_HYSTERESIS := 400.0

func configure(viewer: Node3D, terrain: Node3D) -> void:
	_player = viewer
	_terrain = terrain
	_quality = Quality.current()
	set_process(false)

func append(points: PackedVector3Array, profile: Dictionary, structure: Dictionary) -> void:
	if points.size() < 2:
		return
	var lower := points[0]
	var upper := points[0]
	for point in points:
		lower = lower.min(point)
		upper = upper.max(point)
	entries.append({"points": points, "profile": profile, "structure": structure, "center": (lower + upper) * 0.5, "radius": lower.distance_to(upper) * 0.5})

func prepare_initial() -> void:
	await _refresh(float(_quality.initial_radius))
	if is_inside_tree():
		_last_position = Vector3(INF, INF, INF)
		set_process(true)

func _process(delta: float) -> void:
	var loader := get_node_or_null("/root/LoadingManagerService")
	if loader and loader.is_loading:
		return
	_timer += delta
	if _busy or _timer < 0.5 or not is_instance_valid(_player):
		return
	_timer = 0.0
	if _player.global_position.distance_squared_to(_last_position) >= 250.0 * 250.0:
		_refresh(float(_quality.view_distance) + float(_quality.prefetch))

func _refresh(radius: float) -> void:
	if _busy:
		return
	_busy = true
	var position := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
	var candidates: Array[Dictionary] = []
	var retention := float(_quality.view_distance) + float(_quality.prefetch) + 1000.0
	for id in active.keys():
		if position.distance_to(entries[id].center) > retention + float(entries[id].radius):
			active[id].node.queue_free()
			active.erase(id)
	for id in entries.size():
		var entry: Dictionary = entries[id]
		var distance := position.distance_to(entry.center)
		if distance > radius + float(entry.radius):
			continue
		var detail_limit := float(_quality.rail_detail) + float(entry.radius)
		# 상세/간략 경계에서 같은 청크가 반복 재생성되지 않도록 상세 상태를 여유 거리만큼 유지한다.
		if active.has(id) and active[id].detailed:
			detail_limit += DETAIL_HYSTERESIS
		var detailed := distance <= detail_limit
		if active.has(id) and active[id].detailed == detailed:
			continue
		candidates.append({"id": id, "distance": distance, "detailed": detailed})
	candidates.sort_custom(func(a, b): return a.distance < b.distance)
	for candidate in candidates:
		if not is_inside_tree():
			return
		if is_instance_valid(_player) and _player.global_position.distance_squared_to(position) > 250.0 * 250.0:
			break
		var id: int = candidate.id
		var entry: Dictionary = entries[id]
		var node := TrackBuilder.build(entry.points, entry.profile, entry.structure, float(_quality.view_distance), _terrain, candidate.detailed)
		node.name = "RailChunk_%d" % id
		var formation := Formation.build(entry.points, _terrain, entry.structure)
		if formation:
			node.add_child(formation)
			# 노반은 월드 좌표로 생성되므로 선로 루트의 이동을 상쇄한다.
			formation.position = -node.position
		add_child(node)
		if active.has(id):
			active[id].node.queue_free()
		active[id] = {"node": node, "detailed": candidate.detailed}
		await get_tree().process_frame
	_last_position = position
	_busy = false
