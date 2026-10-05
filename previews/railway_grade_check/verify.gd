extends SceneTree
## 전체 지도 없이 객차의 경사와 양방향 배치를 확인한다.
const Route = preload("res://scripts/terrain/railway_route.gd")
const Service = preload("res://scripts/terrain/railway_train_service.gd")

func _initialize() -> void:
	var route := Route.new()
	route.configure(PackedVector3Array([Vector3.ZERO, Vector3(0, 50, -500), Vector3(0, 50, -1000)]), [])
	var train := Node3D.new()
	for i in range(4):
		train.add_child(Node3D.new())
	var service := Service.new()
	service.profile = {"id": "donghae", "car_length_m": 20.0, "car_gap_m": 0.6}
	for direction in [0, 1]:
		service._pose(train, 250.0, direction, route)
		for car in train.get_children():
			var forward: Vector3 = -car.basis.z
			assert(absf(absf(forward.y) - 0.0995037) < 0.0001, "경사 기울기 누락")
			assert(forward.z < 0 if direction == 0 else forward.z > 0, "역방향 배치 오류")
			assert(absf(car.position.y + car.position.z * 0.1) < 0.0001, "접지 높이 오류")
	var boundary := float(route.distances[1])
	service._pose(train, boundary + 10.0 - 0.01, 0, route)
	var before: Basis = train.get_child(0).basis
	service._pose(train, boundary + 10.0 + 0.01, 0, route)
	var after: Basis = train.get_child(0).basis
	assert(before.z.angle_to(after.z) < 0.001, "경사 경계에서 기울기 급변")
	print("GRADE PASS: 4 cars, both directions, contact height, continuous slope boundary")
	train.free()
	service.free()
	quit(0)
