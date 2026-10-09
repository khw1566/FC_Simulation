extends SceneTree

const Roads = preload("res://scripts/terrain/road_batch_builder.gd")
const Mesh_ = preload("res://scripts/terrain/building_mesh_builder.gd")
const Collision = preload("res://scripts/terrain/building_collision_stream.gd")
const Cache = preload("res://scripts/core/threaded_scene_cache.gd")
const Track = preload("res://scripts/terrain/railway_track_builder.gd")
var failures := 0

func check(label: String, value: bool) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var ground := func(x: float, z: float, fallback: float) -> float: return 10.0 + x * 0.001
	var water := func(x: float, z: float) -> float: return 0.0
	var roads := [
		{"id": "a", "type": "primary", "width": 10.0, "points": [[0, 0, 0], [100, 0, 0], [200, 0, 50]]},
		{"id": "b", "type": "footway", "width": 3.0, "points": [[0, 0, 10], [50, 0, 10]]},
		{"id": "c", "type": "track", "width": 4.0, "points": [[0, 0, 20], [60, 0, 20]]},
		{"id": "d", "type": "primary", "width": 12.0, "bridge": true, "points": [[0, 0, 100], [80, 0, 100]]},
		{"id": "e", "type": "primary", "width": 8.0, "tunnel": true, "points": [[0, 0, 200], [300, 0, 200]]},
	]
	Roads.attach_geometry_keys(roads)
	check("geometry keys", roads.all(func(r): return str(r._geometry_key).length() > 0))
	var holder := [null]
	var task := WorkerThreadPool.add_task(func(): holder[0] = Roads.compute(roads, ground, water, Vector2.ZERO, Vector2.ZERO))
	WorkerThreadPool.wait_for_task_completion(task)
	var result: Dictionary = holder[0]
	check("paved arrays", result.paved.size() == 1)
	check("walking arrays", result.walking.size() == 1)
	check("unpaved arrays", result.unpaved.size() == 1)
	print("  bridge=%d tunnel=%d segments=%d" % [result.bridge.size(), result.tunnel.size(), result.tunnel_segments.size()])
	check("bridge shape per bridge mesh", result.bridge_shapes.size() == result.bridge.size())
	if not result.bridge_shapes.is_empty():
		check("bridge shape faces", result.bridge_shapes[0].get_faces().size() == result.bridge[0][Mesh.ARRAY_VERTEX].size())

	var buildings := [
		{"polygon": [[0, 0], [30, 0], [30, 30], [0, 30]], "height": 40.0},
		{"polygon": [[100, 0], [108, 0], [108, 8], [100, 8]], "height": 6.0},
		{"center": [200, 0, 0], "size": [20, 30, 20]},
	]
	var arrays: Dictionary = Mesh_.compute_arrays(buildings, ground)
	var chunk := Node3D.new()
	root.add_child(chunk)
	Mesh_.apply_arrays(arrays, chunk, StandardMaterial3D.new(), ground)
	var meshes := 0
	var with_faces := 0
	for container in chunk.get_children():
		for child in container.get_children():
			if child is MeshInstance3D:
				meshes += 1
				if child.has_meta("collision_faces") and child.get_meta("collision_faces").size() % 3 == 0:
					with_faces += 1
	check("building faces meta", meshes > 0 and meshes == with_faces)

	var stream := Collision.new()
	var chunks := {Vector3i.ZERO: {"node": chunk, "center_2d": Vector2.ZERO}}
	stream.update(chunks, Vector2.ZERO, 5000.0)
	check("no collision at high clearance", not chunk.has_meta("building_collision"))
	stream.update(chunks, Vector2.ZERO, 50.0)
	for i in 200:
		await process_frame
		stream.update(chunks, Vector2.ZERO, 50.0)
		if stream._jobs.is_empty():
			break
	var bodies := 0
	for container in chunk.get_children():
		for child in container.get_children():
			if child.get_node_or_null("BuildingCollision"):
				bodies += 1
	check("collision bodies attached", bodies == meshes)
	stream.update(chunks, Vector2(5000, 0), 50.0)
	await process_frame
	await process_frame
	var remaining := 0
	for container in chunk.get_children():
		for child in container.get_children():
			if child.get_node_or_null("BuildingCollision"):
				remaining += 1
	check("collision released far away", remaining == 0 and not chunk.has_meta("building_collision"))
	# 해제 직후 재요청 시 중복 부착 방지
	stream.update(chunks, Vector2.ZERO, 50.0)
	stream._release(chunk)
	stream.update(chunks, Vector2.ZERO, 50.0)
	for i in 200:
		await process_frame
		stream.update(chunks, Vector2.ZERO, 50.0)
		if stream._jobs.is_empty():
			break
	var doubled := 0
	for container in chunk.get_children():
		for child in container.get_children():
			var count := 0
			for c in child.get_children():
				if c.name.begins_with("BuildingCollision"):
					count += 1
			doubled = maxi(doubled, count)
	check("no duplicate collision after re-request", doubled == 1)
	stream.dispose()

	var cache := Cache.new()
	var builder := func() -> PackedScene:
		var node := Node3D.new()
		var scene := PackedScene.new()
		scene.pack(node)
		node.free()
		return scene
	var first := cache.request("x", builder)
	check("cache first request pending", not first)
	var ready := false
	for i in 200:
		await process_frame
		if cache.request("x", builder):
			ready = true
			break
	check("cache ready", ready and cache.instantiate("x") != null)
	var failing := func() -> PackedScene: return null
	cache.request_now("bad", failing)
	check("failed key cached as ready", cache.request("bad", failing) and cache.instantiate("bad") == null)

	var a := Track._material(Color.RED, 0.7)
	var b := Track._material(Color.RED, 0.7)
	check("track material shared", a == b and is_equal_approx(a.metallic, 0.7))
	print("FAILURES=", failures)
	quit(failures)
