extends Node3D
const Layout = preload("res://scripts/terrain/regional_airport_layout.gd")
var _airports: Array[Dictionary] = []

func setup(catalog: Dictionary, map_config) -> void:
	var meta := {"world_size_meters": map_config.world_size_meters, "bbox": {"south": map_config.bbox_south, "north": map_config.bbox_north, "west": map_config.bbox_west, "east": map_config.bbox_east}}
	for spec in catalog.airports:
		if not Layout.in_map(spec, meta):
			continue
		var packed := load(str(spec.scene_path)) as PackedScene
		if packed == null:
			push_error("공항 씬 누락: " + str(spec.scene_path))
			continue
		var model := packed.instantiate() as Node3D
		model.transform = Layout.frame(spec, meta)
		add_child(model)
		_airports.append({"node": model, "spec": spec, "bounds": Layout.bounds(spec)})
		var label := Label3D.new()
		label.text = str(spec.name_ko)
		label.position = Vector3(0, 55, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.visibility_range_end = 15000
		model.add_child(label)
	print("[RegionalAirportManager] 공항 배치: ", _airports.size())

func replaces_building(x: float, z: float) -> bool:
	for entry in _airports:
		var point: Vector3 = entry.node.to_local(Vector3(x, entry.node.global_position.y, z))
		if entry.bounds.has_point(Vector2(point.x, point.z)):
			return true
	return false
