extends SceneTree

func _init():
	var root_node = root
	var svc = root_node.get_node_or_null("MapSelectionService")
	if not svc:
		svc = load("res://scripts/services/map_selection_service.gd").new()
		svc.name = "MapSelectionService"
		root_node.add_child(svc)

	svc.select_map_by_id("kanmon_straits")
	print("[Test] Selected Map: ", svc.selected_map.id, " WorldSize: ", svc.selected_map.world_size_meters)

	var scene = load("res://scenes/main_world.tscn").instantiate()
	root_node.add_child(scene)
	print("[Test] main_world scene instantiated successfully with kanmon_straits!")
	quit()

