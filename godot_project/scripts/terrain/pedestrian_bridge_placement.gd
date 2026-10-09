extends Node3D
class_name PedestrianBridgePlacement

const CATALOG := "res://assets/generated/pedestrian_bridges/placements.json"
const Geometry = preload("res://scripts/terrain/bridge_geometry.gd")
const DeckBuilder = preload("res://scripts/terrain/bridge_landmark_builder.gd")
const Collision = preload("res://scripts/terrain/structure_collision.gd")
var replaced_osm_ids: Dictionary = {}
var placed: Array[Node3D] = []

func setup(map_config, terrain: Node3D) -> void:
	if map_config == null or not FileAccess.file_exists(CATALOG):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not data is Dictionary or not map_config.id in data.get("map_ids", []):
		return
	for spec in data.placements:
		if not _inside(spec.geometry[0], map_config) or not _inside(spec.geometry[-1], map_config):
			continue
		var packed := load(str(spec.scene_path)) as PackedScene
		if packed == null:
			push_error("교량 에셋 로드 실패: " + str(spec.scene_path))
			continue
		var model := packed.instantiate() as Node3D
		var a_marker := model.get_node_or_null(str(spec.markers[0])) as Node3D
		var b_marker := model.get_node_or_null(str(spec.markers[1])) as Node3D
		if a_marker == null or b_marker == null:
			model.free()
			push_error("교량 배치 기준점 누락: " + str(spec.id))
			continue
		var a := _project(spec.geometry[0], map_config, terrain)
		var b := _project(spec.geometry[-1], map_config, terrain)
		a.y += float(spec.clearance_m)
		b.y += float(spec.clearance_m)
		var direction := b - a
		var marker_distance := a_marker.position.distance_to(b_marker.position)
		if direction.length() < 1.0 or marker_distance < 1.0:
			model.free()
			continue
		var basis := Basis.looking_at(-direction.normalized(), Vector3.UP)
		basis = basis * Basis.from_scale(Vector3(1, 1, direction.length() / marker_distance))
		var center := (a_marker.position + b_marker.position) * 0.5
		model.transform = Transform3D(basis, (a + b) * 0.5 - basis * center)
		var rise := _terrain_clearance(model, spec, terrain, a_marker.position, b_marker.position)
		model.position.y += rise
		a.y += rise
		b.y += rise
		model.name = str(spec.id)
		model.set_meta("source_osm_ids", spec.osm_ids)
		model.set_meta("placement_accuracy", spec.accuracy)
		model.set_meta("bank_a_world", a)
		model.set_meta("bank_b_world", b)
		model.set_meta("terrain_clearance_adjustment_m", rise)
		add_child(model)
		Collision.add_trimesh(model)
		placed.append(model)
		for id in spec.osm_ids:
			replaced_osm_ids[str(id)] = true
		_add_approaches(spec, map_config, terrain, a, b)
		if spec.id == "seonbawi_bridge":
			_add_pier_foundations(model, terrain)

func _terrain_clearance(model: Node3D, spec: Dictionary, terrain: Node3D, a: Vector3, b: Vector3) -> float:
	if not is_instance_valid(terrain):
		return 0.0
	var rise := 0.0
	var count := maxi(4, ceili((model.transform * a).distance_to(model.transform * b) / 5.0))
	for index in range(count + 1):
		for side in [-0.5, 0.0, 0.5]:
			var point: Vector3 = model.transform * (a.lerp(b, float(index) / count) + Vector3.RIGHT * float(spec.width_m) * float(side))
			var ground_y: float = float(terrain.call("get_terrain_elevation", point.x, point.z))
			rise = maxf(rise, ground_y + 0.10 - point.y)
	return rise

func _add_pier_foundations(model: Node3D, terrain: Node3D) -> void:
	if not is_instance_valid(terrain):
		return
	var geometry := Geometry.new()
	for z in [-48.0, -16.0, 16.0, 48.0]:
		for x in [-6.972, 6.972]:
			var foot := model.transform * Vector3(x,0,z)
			var ground_y: float = float(terrain.call("get_terrain_elevation", foot.x, foot.z))
			if foot.y > ground_y:
				geometry.beam(Vector3(foot.x,ground_y-0.5,foot.z), foot + Vector3.UP * 0.1, 2.4, 2.4)
	var node := Node3D.new()
	node.name = "seonbawi_bridge_foundations"
	geometry.finish(node)
	add_child(node)
	Collision.add_trimesh(node)

func _add_approaches(spec: Dictionary, map_config, terrain: Node3D, bank_a: Vector3, bank_b: Vector3) -> void:
	if spec.approaches.is_empty():
		return
	var geometry := Geometry.new()
	for side in spec.approaches.size():
		var coordinates: Array = spec.approaches[side]
		var points: Array[Vector3] = []
		for coordinate in coordinates:
			var point := _project(coordinate, map_config, terrain)
			point.y += 0.20
			points.append(point)
		if side == 0:
			points[-1] = bank_a
		else:
			points[0] = bank_b
		for index in range(1, points.size()):
			var count := maxi(1, ceili(points[index - 1].distance_to(points[index]) / 4.0))
			for step in count:
				var a := points[index - 1].lerp(points[index], float(step) / count)
				var b := points[index - 1].lerp(points[index], float(step + 1) / count)
				if is_instance_valid(terrain):
					a.y = maxf(a.y, float(terrain.call("get_terrain_elevation", a.x, a.z)) + 0.10)
					b.y = maxf(b.y, float(terrain.call("get_terrain_elevation", b.x, b.z)) + 0.10)
				var direction := (b - a).normalized()
				var lateral := Vector3(direction.z, 0, -direction.x).normalized()
				DeckBuilder.deck_segment(geometry, a, b, lateral, float(spec.approach_width_m))
	var node := Node3D.new()
	node.name = str(spec.id) + "_approaches"
	geometry.finish(node)
	add_child(node)
	Collision.add_trimesh(node)

func replaces_road(road: Dictionary) -> bool:
	return replaced_osm_ids.has(str(road.get("osm_id", "")))

func _inside(point: Dictionary, map_config) -> bool:
	return float(point.lon) >= map_config.bbox_west and float(point.lon) <= map_config.bbox_east and float(point.lat) >= map_config.bbox_south and float(point.lat) <= map_config.bbox_north

func _project(point: Dictionary, map_config, terrain: Node3D) -> Vector3:
	var x: float = ((float(point.lon) - map_config.bbox_west) / (map_config.bbox_east - map_config.bbox_west) - 0.5) * map_config.world_size_meters
	var z: float = ((map_config.bbox_north - float(point.lat)) / (map_config.bbox_north - map_config.bbox_south) - 0.5) * map_config.world_size_meters
	var y := 0.0
	if is_instance_valid(terrain):
		y = float(terrain.call("get_terrain_elevation", x, z))
	return Vector3(x, y, z)
