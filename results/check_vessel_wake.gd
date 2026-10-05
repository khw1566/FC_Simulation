extends SceneTree

const Wake = preload("res://scripts/water/vessel_wake.gd")
const Route = preload("res://scripts/water/vessel_route.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/vessels/traffic.json"))
	var failures: Array[String] = []
	var moored := 0
	var sailing := 0
	for entry in catalog.maps.ulsan_metro_80km.entries:
		var route := Route.new()
		route.configure(entry, 0.0, catalog.settings)
		if entry.mode == "moored":
			moored += 1
			if route.sample(0).origin != route.sample(10000).origin or route.moving_speed(100) != 0:
				failures.append("정박 선박 이동")
		else:
			sailing += 1
	var wake := Wake.new()
	wake.configure({"length_m":20.0, "beam_m":5.0}, catalog.settings)
	root.add_child(wake)
	for step in 40:
		wake.advance(0.4, Transform3D(Basis.IDENTITY, Vector3(0, 0, -step * 1.2)), 3.0)
	if wake.mesh == null:
		failures.append("운항 항적 미생성")
	for step in 180:
		wake.advance(0.4, Transform3D.IDENTITY, 0.0)
	if wake.mesh != null or not wake._samples.is_empty():
		failures.append("정박 후 항적 미소멸")
	var large := Wake.new()
	large.configure({"length_m":250.0, "beam_m":40.0}, catalog.settings)
	if large._lifetime <= wake._lifetime or large._beam <= wake._beam:
		failures.append("선박 크기 비례 미적용")
	large.free()
	wake.free()
	print(JSON.stringify({"sailing":sailing,"moored":moored,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
