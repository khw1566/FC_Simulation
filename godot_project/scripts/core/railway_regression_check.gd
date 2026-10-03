extends SceneTree

const Route = preload("res://scripts/terrain/railway_route.gd")
const Timetable = preload("res://scripts/terrain/railway_timetable.gd")
const TrainBuilder = preload("res://scripts/terrain/railway_train_builder.gd")
const TrainService = preload("res://scripts/terrain/railway_train_service.gd")
const TrackBuilder = preload("res://scripts/terrain/railway_track_builder.gd")
const WorldManager = preload("res://scripts/terrain/railway_world_manager.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/railway/services.json"))
	var network: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/railway/network.json"))
	var fixture := Node3D.new()
	root.add_child(fixture)
	var metrics := {}
	for profile in settings.services:
		var route := Route.new()
		route.configure(PackedVector3Array([Vector3(0,0,0), Vector3(0,0,-600), Vector3(100,0,-1200), Vector3(100,0,-1800)]), [{"name":"검증역", "point_index":2}])
		_expect(absf(route.sample(600).origin.z + 600) < 0.01, "거리 기반 경로 보간")
		var table := Timetable.new()
		table.configure(route, profile, false)
		var previous := 0.0
		var max_speed := 0.0
		for step in range(1, ceili(table.duration * 10)):
			var distance: float = table.distance_at(step / 10.0)
			_expect(distance >= previous - 0.001, "정차 포함 이동 거리 단조 증가")
			max_speed = maxf(max_speed, (distance - previous) * 10.0)
			previous = distance
		_expect(max_speed <= float(profile.speed_mps) + 0.01, "노선 속도 상한")
		_expect(is_equal_approx(table.distance_at(table.duration), route.length), "운행 종료 위치")
		var dwell: Dictionary = table.phases[1]
		_expect(is_equal_approx(table.distance_at(dwell.start + 1), table.distance_at(dwell.end - 1)), "역 정차 중 위치 유지")
		var reverse := Timetable.new()
		reverse.configure(route, profile, true)
		_expect(is_equal_approx(reverse.phases[1].distance, route.length - route.stops[0].distance), "역방향 정차 거리")
		var train := TrainBuilder.build(profile)
		fixture.add_child(train)
		_expect(train.get_child_count() == int(profile.cars), "노선별 객차 수")
		var service := TrainService.new()
		service.configure(route, profile, null, 1.0, route)
		fixture.add_child(service)
		service.set_process(false)
		service.update_at(80.0)
		_expect(service.active.has("0:0"), "첫 출발편 생성")
		service.update_at(float(profile.interval_seconds) + 10.0)
		_expect(service.active.has("0:1"), "설정 주기 후 다음 편 생성")
		service.update_at(100000.0)
		_expect(service.active.size() <= int(profile.max_active_per_direction) * 2, "운행 모델 수 상한")
		var track := TrackBuilder.build(route.points, profile, {"bridge":false}, 1000)
		fixture.add_child(track)
		_expect(track.get_child_count() >= 6, "도상·레일·침목·전차선 생성")
		var real: Dictionary = network.routes[0] if profile.id == "donghae" else network.routes[1]
		_expect(real.points.size() > 100 and real.opposite_points.size() > 100, "실제 양방향 연결 선로")
		_expect(real.points[0] != real.opposite_points[0], "방향별 별도 선로")
		_expect(real.stops.size() == (10 if profile.id == "donghae" else 2), "실제 정차역 연결")
		var geographic_length := 0.0
		for index in range(1, real.points.size()):
			var a: Array = real.points[index - 1]
			var b: Array = real.points[index]
			geographic_length += Vector2((b[0]-a[0])*90500, (b[1]-a[1])*111000).length()
		_expect(geographic_length > 30000, "실제 경로 30km 이상 연결")
		metrics[profile.id] = {"route_vertices": real.points.size(), "opposite_vertices": real.opposite_points.size(), "stops": real.stops, "length_m": geographic_length, "cars": profile.cars, "fixture_duration_seconds": table.duration, "observed_max_speed": max_speed}
	# 월드 통합은 전체 지도 대신 메타데이터와 지형 없는 작은 선형으로 검증한다.
	var manager := WorldManager.new()
	fixture.add_child(manager)
	var map_config = preload("res://scripts/models/map_config_model.gd").create_from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/ulsan_metro_80km/map_meta.json")))
	var test_track := {"points": [[129.3,35.5],[129.31,35.5]], "bridge":false, "tunnel":false}
	manager._project_track(test_track, map_config, null)
	var projected: Dictionary = manager._project_route(test_track.points, [{"name":"검증", "point_index":1}], map_config, null)
	_expect(projected.points.size() > 2, "열차와 선로의 세분화 경로 공유")
	_expect(projected.stops[0].point_index == projected.points.size()-1, "세분화 후 정차 지점 보존")
	# 실자료 전 구간의 정밀 좌표 연결을 검사하되 메시나 높이맵은 생성하지 않는다.
	for track_data in network.tracks:
		manager._project_track(track_data, map_config, null)
	for route_data in network.routes:
		for direction in ["points", "opposite_points"]:
			var station_key := "stops" if direction == "points" else "opposite_stops"
			var real_projected: Dictionary = manager._project_route(route_data[direction], route_data[station_key], map_config, null)
			_expect(real_projected.points.size() >= route_data[direction].size(), "실제 경로 정밀 좌표와 선로 일치: " + route_data.service + "/" + direction)
			for index in range(1, route_data[direction].size()):
				var a: String = manager._key(route_data[direction][index-1])
				var b: String = manager._key(route_data[direction][index])
				_expect(manager._segments.has(a+"|"+b) or manager._segments.has(b+"|"+a), "운행 경로 모든 간선이 실제 선로에 존재")
	var result := {"checks":checks,"failures":failures,"tracks":network.tracks.size(),"services":metrics,"full_map_loaded":false}
	var file := FileAccess.open("res://../results/261004_RailwayValidation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("[철도 검증] 검사=", checks, " 실패=", failures.size())
	fixture.free()
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
