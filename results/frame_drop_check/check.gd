extends SceneTree

func _init() -> void:
	var paths := [
		"res://scripts/terrain/building_road_manager.gd",
		"res://scripts/terrain/vector_data_stream.gd",
		"res://scripts/terrain/road_batch_builder.gd",
		"res://scripts/terrain/building_collision_stream.gd",
		"res://scripts/terrain/building_batch_assembler.gd",
		"res://scripts/terrain/building_mesh_builder.gd",
		"res://scripts/terrain/industrial_asset_factory.gd",
		"res://scripts/terrain/industrial_zone_manager.gd",
		"res://scripts/terrain/railway_track_builder.gd",
		"res://scripts/terrain/railway_night_lighting.gd",
		"res://scripts/water/vessel_model_factory.gd",
		"res://scripts/water/vessel_world_manager.gd",
		"res://scripts/core/threaded_scene_cache.gd",
	]
	var failed := 0
	for path in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL ", path)
		else:
			print("OK   ", path)
	print("FAILED=", failed)
	quit(failed)
