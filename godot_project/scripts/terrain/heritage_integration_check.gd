extends SceneTree

const Manager = preload("res://scripts/terrain/heritage_landmark_manager.gd")
const Terrain = preload("res://scripts/terrain/terrain_chunk_manager.gd")
const MapConfig = preload("res://scripts/models/map_config_model.gd")

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	var reports: Array = []
	var passed := true
	for map_id in ["ulsan_metro_80km", "southeast_mega_140km", "kanmon_straits"]:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/" + map_id + "/map_meta.json"))
		var config = MapConfig.create_from_dict(meta)
		var terrain := Terrain.new()
		terrain.terrain_world_size = config.world_size_meters
		terrain.min_elevation = config.min_elevation
		terrain.max_elevation = config.max_elevation
		terrain._full_heightmap_image = Image.load_from_file(config.heightmap_path)
		terrain._full_heightmap_image.convert(Image.FORMAT_RF)
		var manager := Manager.new()
		root.add_child(manager)
		manager.setup(config, terrain)
		await physics_frame
		await physics_frame
		var expected := 0 if map_id == "kanmon_straits" else 2
		var valid: bool = manager.placements.size() == expected
		var checks: Array = []
		for placement in manager.placements:
			var model: Node3D = placement.model
			var spec: Dictionary = placement.spec
			var start := Vector2(spec.walls[0].points[0][0], spec.walls[0].points[0][1])
			var end := Vector2(spec.walls[0].points[1][0], spec.walls[0].points[1][1])
			var sample := start + (end - start).normalized() * 0.7
			var p := model.to_global(Vector3(sample.x, 0, sample.y))
			valid = valid and manager.replaces_building(p.x, p.z)
			valid = valid and not manager.replaces_building(p.x + 1000, p.z + 1000)
			var meshes := model.find_children("*", "MeshInstance3D", true, false)
			var bodies := model.find_children("*", "StaticBody3D", true, false)
			valid = valid and not meshes.is_empty() and not bodies.is_empty()
			var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1800, p - Vector3.UP * 100)
			var hit := manager.get_world_3d().direct_space_state.intersect_ray(query)
			valid = valid and not hit.is_empty()
			var ground_fit := true
			var source := (load(str(spec.scene_path)) as PackedScene).instantiate()
			for mesh in meshes:
				if str(mesh.name).begins_with("gate_") or mesh.name == "GateFoundations":
					continue
				var fitted: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var original: PackedVector3Array = source.get_node(NodePath(str(mesh.name))).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for i in range(0, fitted.size(), maxi(1, fitted.size() / 40)):
					var world := model.to_global(fitted[i])
					ground_fit = ground_fit and absf(fitted[i].y - original[i].y - terrain.get_terrain_elevation(world.x, world.z)) < 0.02
			source.free()
			valid = valid and ground_fit
			var passage_clear := true
			var floor_collision := true
			if spec.has("gate"):
				var floor_y: float = model.get_node("gate_wood").mesh.get_aabb().position.y - 0.05
				var gate := Vector3(spec.gate.x, floor_y, spec.gate.z)
				var passage := PhysicsRayQueryParameters3D.create(model.to_global(gate + Vector3(0, 1.6, 7)), model.to_global(gate + Vector3(0, 1.6, -7)))
				passage_clear = manager.get_world_3d().direct_space_state.intersect_ray(passage).is_empty()
				var floor_ray := PhysicsRayQueryParameters3D.create(model.to_global(gate + Vector3.UP * 15), model.to_global(gate + Vector3.UP * 2))
				floor_collision = not manager.get_world_3d().direct_space_state.intersect_ray(floor_ray).is_empty()
			valid = valid and passage_clear and floor_collision
			checks.append({"id": spec.id, "mesh_batches": meshes.size(), "collision_bodies": bodies.size(), "wall_ray_hit": not hit.is_empty(), "terrain_fit": ground_fit, "gate_passage_clear": passage_clear, "gate_floor_collision": floor_collision})
		reports.append({"map": map_id, "expected": expected, "loaded": manager.placements.size(), "passed": valid, "landmarks": checks})
		passed = passed and valid
		manager.free()
		terrain.free()
	var result := {"passed": passed, "maps": reports}
	var file := FileAccess.open("res://../results/ulsan_heritage_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print(JSON.stringify(result))
	quit(0 if passed else 1)

