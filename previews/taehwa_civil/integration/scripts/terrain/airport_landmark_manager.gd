extends Node3D
class_name AirportLandmarkManager

var _spec: Dictionary = {}
var _loaded: bool = false
var _regional: Node3D

func setup(placement_path: String, map_config, terrain: Node3D) -> void:
	if placement_path.is_empty() or map_config == null:
		return
	var file := FileAccess.open(placement_path, FileAccess.READ)
	if file == null:
		push_warning("공항 배치 파일을 읽지 못했습니다: " + placement_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	if parsed.has("airports"):
		_regional = preload("res://scripts/terrain/regional_airport_manager.gd").new()
		add_child(_regional)
		_regional.setup(parsed, map_config)
		return
	if not parsed.has("anchor"):
		return
	_spec = parsed
	var packed := load(str(_spec.get("scene_path", ""))) as PackedScene
	if packed == null:
		return
	var anchor: Dictionary = _spec.anchor
	position.x = ((float(anchor.lon) - map_config.bbox_west) / (map_config.bbox_east - map_config.bbox_west) - 0.5) * map_config.world_size_meters
	position.z = ((map_config.bbox_north - float(anchor.lat)) / (map_config.bbox_north - map_config.bbox_south) - 0.5) * map_config.world_size_meters
	rotation.y = deg_to_rad(float(_spec.rotation_y_degrees))
	position.y = float(_spec.reference_elevation_m)
	if is_instance_valid(terrain) and terrain.has_method("get_terrain_elevation"):
		var floor_y: float = -INF
		for building in _spec.buildings:
			for sx in [-0.5, 0.0, 0.5]:
				for sz in [-0.5, 0.0, 0.5]:
					var p := Vector3(float(building.center_xz[0]) + float(building.size_xz[0]) * sx, 0, float(building.center_xz[1]) + float(building.size_xz[1]) * sz)
					var world := to_global(p)
					floor_y = maxf(floor_y, float(terrain.call("get_terrain_elevation", world.x, world.z)))
		position.y = floor_y + 0.15
		var graded_floor = terrain.get("airport_floor_y")
		if graded_floor is float and not is_nan(graded_floor):
			position.y = graded_floor
		_add_terrain_foundations(terrain)
	var model := packed.instantiate()
	add_child(model)
	_loaded = true
	print("[AirportLandmarkManager] 울산공항 배치 완료: ", global_position)

func replaces_building(world_x: float, world_z: float) -> bool:
	if _regional != null:
		return _regional.replaces_building(world_x, world_z)
	if not _loaded:
		return false
	var local := to_local(Vector3(world_x, global_position.y, world_z))
	for building in _spec.buildings:
		if absf(local.x - float(building.center_xz[0])) <= float(building.size_xz[0]) * 0.5 and absf(local.z - float(building.center_xz[1])) <= float(building.size_xz[1]) * 0.5:
			return true
	return false

func _add_terrain_foundations(terrain: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.47, 0.48, 0.47)
	for building in _spec.buildings:
		var low_y: float = global_position.y
		for sx in [-0.5, 0.0, 0.5]:
			for sz in [-0.5, 0.0, 0.5]:
				var world := to_global(Vector3(float(building.center_xz[0]) + float(building.size_xz[0]) * sx, 0, float(building.center_xz[1]) + float(building.size_xz[1]) * sz))
				low_y = minf(low_y, float(terrain.call("get_terrain_elevation", world.x, world.z)))
		var depth: float = maxf(8.0, global_position.y - low_y + 2.0)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(float(building.size_xz[0]), depth, float(building.size_xz[1]))
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.position = Vector3(float(building.center_xz[0]), -depth / 2, float(building.center_xz[1]))
		instance.visibility_range_end = 14000.0
		add_child(instance)
		instance.create_trimesh_collision()
