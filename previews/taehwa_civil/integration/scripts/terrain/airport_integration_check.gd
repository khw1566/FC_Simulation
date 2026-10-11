extends SceneTree

const MapConfig = preload("res://scripts/models/map_config_model.gd")
const Terrain = preload("res://scripts/terrain/terrain_chunk_manager.gd")
const Airport = preload("res://scripts/terrain/airport_landmark_manager.gd")
const Grader = preload("res://scripts/terrain/airfield_terrain_grader.gd")
const Layout = preload("res://scripts/terrain/airfield_layout.gd")

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/ulsan_metro_80km/map_meta.json"))
	var config = MapConfig.create_from_dict(meta)
	var terrain := Terrain.new()
	terrain.terrain_world_size = config.world_size_meters
	terrain.min_elevation = config.min_elevation
	terrain.max_elevation = config.max_elevation
	terrain._full_heightmap_image = Image.load_from_file(config.heightmap_path)
	terrain._full_heightmap_image.convert(Image.FORMAT_RF)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.airport_placement_path))
	terrain.airport_floor_y = Grader.apply(terrain._full_heightmap_image, spec, meta, config.min_elevation, config.max_elevation)
	var world := Node3D.new()
	root.add_child(world)
	var airport := Airport.new()
	world.add_child(airport)
	airport.setup(config.airport_placement_path, config, terrain)
	var anchor := airport.global_position
	var passed: bool = airport.replaces_building(anchor.x, anchor.z)
	passed = passed and not airport.replaces_building(anchor.x + 1000, anchor.z)
	var geometry := airport.find_children("Geometry_*", "MeshInstance3D", true, false)
	passed = passed and geometry.size() == 6
	var triangles: int = 0
	for node in geometry:
		triangles += node.mesh.get_faces().size() / 3
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(anchor + Vector3(0, 80, 0), anchor + Vector3(0, -20, 0))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	passed = passed and not hit.is_empty()
	var runway_checks: Array = []
	var frame := Layout.world_frame(spec, meta)
	var clear: bool = true
	for z in [-10.0, -500.0, -1000.0, -1500.0, -1990.0]:
		for x in [-20.0, 0.0, 20.0]:
			var point := frame * Vector3(x, 0, z)
			point.y = anchor.y + Layout.height_at(x, z, spec)
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 10, point - Vector3.UP * 2)
			var runway_hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
			var ground: float = terrain.get_terrain_elevation(point.x, point.z)
			var valid: bool = not runway_hit.is_empty() and ground < point.y and absf(runway_hit.position.y - point.y) < 0.12
			clear = clear and valid
			runway_checks.append({"x": x, "station_m": -z, "valid": valid, "ground_clearance_m": point.y - ground})
	var light_groups := airport.find_children("Lamps_*", "MultiMeshInstance3D", true, false)
	var lamp_count: int = 0
	var light_positions_valid: bool = true
	for group in light_groups:
		lamp_count += group.multimesh.instance_count
		light_positions_valid = light_positions_valid and group.multimesh.get_instance_transform(0).origin.distance_to(group.multimesh.get_instance_transform(1).origin) > 0.5
	passed = passed and clear and light_groups.size() == 5 and lamp_count > 200 and light_positions_valid
	var result := {
		"passed": passed,
		"world_anchor": [anchor.x, anchor.y, anchor.z],
		"batched_meshes": geometry.size(),
		"triangles": triangles,
		"collision_hit": not hit.is_empty(),
		"runway_checks": runway_checks,
		"lamp_count": lamp_count,
		"light_batches": light_groups.size(),
		"serialized_light_positions_valid": light_positions_valid,
		"scope": "실제 높이맵 정지·배치·건물 및 활주로 충돌·등화 그룹 검사. 전체 게임 수동 비행은 별도."
	}
	var file := FileAccess.open("res://../results/ulsan_airport_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print(JSON.stringify(result))
	terrain.free()
	world.free()
	quit(0 if passed else 1)

