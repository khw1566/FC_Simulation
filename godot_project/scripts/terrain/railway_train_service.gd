extends Node3D
class_name RailwayTrainService

const Timetable = preload("res://scripts/terrain/railway_timetable.gd")
const TrainBuilder = preload("res://scripts/terrain/railway_train_builder.gd")

var route
var opposite_route
var profile: Dictionary
var time_scale := 1.0
var elapsed := 0.0
var render_distance := 12000.0
var player: Node3D
var timetables: Array = []
var active: Dictionary = {}
var pool: Array[Node3D] = []

func configure(value, settings: Dictionary, viewer: Node3D, scale: float, opposite = null, view_distance: float = 12000.0) -> void:
	route = value
	opposite_route = opposite if opposite != null else value
	profile = settings
	player = viewer
	time_scale = maxf(0.0, scale)
	render_distance = maxf(1.0, view_distance)
	timetables.clear()
	for reverse in [false, true]:
		var timetable := Timetable.new()
		timetable.configure(opposite_route if reverse else route, profile, reverse)
		timetables.append(timetable)
	# 첫 화면에서도 이미 출발한 편성이 노선 전역에 분포하도록 시간을 진행한다.
	elapsed = maxf(timetables[0].duration, timetables[1].duration) + float(profile.direction_offset_seconds)

func _process(delta: float) -> void:
	if route == null:
		return
	elapsed += delta * time_scale
	update_at(elapsed)

func update_at(time: float) -> void:
	var desired := {}
	var interval: float = maxf(1.0, float(profile.interval_seconds))
	for direction in [0, 1]:
		var current_route = route if direction == 0 else opposite_route
		var offset: float = 0.0 if direction == 0 else float(profile.direction_offset_seconds)
		var last: int = floori((time - offset) / interval)
		var first: int = maxi(0, ceili((time - offset - timetables[direction].duration) / interval))
		var candidates: Array = []
		for departure in range(first, last + 1):
			var age: float = time - offset - departure * interval
			if age < 0.0 or age > timetables[direction].duration:
				continue
			var key := "%d:%d" % [direction, departure]
			var distance: float = timetables[direction].distance_at(age)
			var world_distance: float = distance if direction == 0 else current_route.length - distance
			var position: Vector3 = current_route.sample(world_distance).origin
			var viewer_distance := player.global_position.distance_to(position) if is_instance_valid(player) else 0.0
			if viewer_distance > render_distance:
				continue
			candidates.append({"key": key, "distance": world_distance, "viewer_distance": viewer_distance})
		# 출발 순서가 아니라 관찰자와 가까운 편성을 우선 표시한다.
		candidates.sort_custom(func(a, b): return a.viewer_distance < b.viewer_distance)
		for index in mini(candidates.size(), int(profile.max_active_per_direction)):
			var candidate: Dictionary = candidates[index]
			var key: String = candidate.key
			desired[key] = true
			if not active.has(key):
				var train: Node3D
				if pool.is_empty():
					train = TrainBuilder.build(profile)
					add_child(train)
				else:
					train = pool.pop_back()
				train.visible = true
				active[key] = train
			_pose(active[key], float(candidate.distance), direction, current_route)
	for key in active.keys():
		if not desired.has(key):
			var train: Node3D = active[key]
			train.visible = false
			pool.append(train)
			active.erase(key)

func _pose(train: Node3D, head_distance: float, direction: int, current_route) -> void:
	var sign_value: float = 1.0 if direction == 0 else -1.0
	var travelled := 0.0
	for index in train.get_child_count():
		var car := train.get_child(index) as Node3D
		var length: float = float(profile.car_length_m)
		if profile.id == "ktx" and (index == 0 or index == train.get_child_count()-1):
			length = float(profile.get("power_car_length_m", length))
		var distance: float = head_distance - sign_value * (travelled + length * 0.5)
		travelled += length + float(profile.car_gap_m)
		car.visible = distance >= 0.0 and distance <= current_route.length
		if not car.visible:
			continue
		# 앞뒤 대차의 접지 위치로 차체를 놓아 선형 경계에서도 경사를 잇는다.
		var bogie_offset := length * 0.32
		var front: Vector3 = current_route.sample(distance + sign_value * bogie_offset).origin
		var rear: Vector3 = current_route.sample(distance - sign_value * bogie_offset).origin
		var forward := front - rear
		var pose: Transform3D = current_route.sample(distance)
		if forward.length_squared() > 0.0001:
			pose = Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), (front + rear) * 0.5)
		elif direction == 1:
			pose.basis = pose.basis * Basis(Vector3.UP, PI)
		car.transform = pose
