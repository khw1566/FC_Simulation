extends SceneTree

const Manager = preload("res://dam_landmark_manager.gd")
const Terrain = preload("res://terrain_fixture.gd")

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	var manager := Manager.new()
	root.add_child(manager)
	var config := {"id":"ulsan_metro_80km","world_size_meters":80000.0,"bbox_west":128.81256666666667,"bbox_east":129.69843333333336,"bbox_south":35.1841,"bbox_north":35.9049}
	manager.setup(config,terrain,"res://catalog.json","res://")
	assert(manager.placements.size()==5)
	await physics_frame
	await physics_frame
	var checks: Array = []
	for placement in manager.placements:
		var model: Node3D = placement.model
		var spec: Dictionary = placement.spec
		var error := 0.0
		for index in [0,1]:
			var endpoint := model.to_global(Vector3(float(spec.official_length_m)*(index-0.5),0,0))
			var expected := manager._world(spec.axis_lonlat[index],config)
			error = maxf(error,Vector2(endpoint.x,endpoint.z).distance_to(Vector2(expected.x,expected.z)))
		assert(error < 0.05)
		assert(absf(model.position.y-65.35)<0.001)
		assert(not model.find_children("*","StaticBody3D",true,false).is_empty())
		assert(model.find_children("*","MeshInstance3D",true,false).size()==2)
		var query := PhysicsRayQueryParameters3D.create(model.position+Vector3.UP*50,model.position-Vector3.UP*100)
		var hit := manager.get_world_3d().direct_space_state.intersect_ray(query)
		assert(not hit.is_empty())
		assert(absf(float(hit.position.y)-65.45)<0.05)
		checks.append({"id":spec.id,"axis_endpoint_error_m":error,"lod_count":2,"collision":true,"fitted_crest_ray_hit":true})
	manager.setup(config,terrain,"res://catalog.json","res://")
	assert(manager.get_child_count()==5)
	config.id="kanmon_straits"
	manager.setup(config,terrain,"res://catalog.json","res://")
	assert(manager.placements.is_empty())
	config.id="ulsan_uc_west"
	config.bbox_north=35.56
	config.bbox_south=35.53
	config.bbox_west=129.23
	config.bbox_east=129.28
	manager.setup(config,terrain,"res://catalog.json","res://")
	assert(manager.placements.is_empty())
	var file := FileAccess.open("res://fixture_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":true,"checks":checks,"idempotent":true,"unrelated_map_excluded":true,"out_of_bounds_excluded":true},"\t"))
	print("DAMS_FIXTURE_OK")
	quit()
