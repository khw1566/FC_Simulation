extends Node3D
class_name HeritageLandmarkManager

const SPEC_PATH := "res://assets/generated/heritage/placement.json"
var placements: Array[Dictionary] = []
# 배치하지 않는 유적지 주변에서 같은 시설을 나타내는 범용 건물도 생략한다.
var _suppressions: Array[Dictionary] = []
var _height_cache: Dictionary = {}

func setup(config, terrain: Node3D) -> void:
	if config == null or not is_instance_valid(terrain) or not terrain.has_method("get_terrain_elevation"):
		return
	if not FileAccess.file_exists(SPEC_PATH):
		push_warning("성곽 모델 배치 자료가 없습니다.")
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	for spec in data.landmarks:
		var lat: float = spec.anchor.lat
		var lon: float = spec.anchor.lon
		if lat < config.bbox_south or lat > config.bbox_north or lon < config.bbox_west or lon > config.bbox_east:
			continue
		var anchor := Vector3(((lon - config.bbox_west) / (config.bbox_east - config.bbox_west) - 0.5) * config.world_size_meters, 0, ((config.bbox_north - lat) / (config.bbox_north - config.bbox_south) - 0.5) * config.world_size_meters)
		if spec.has("suppress_building_names"):
			_suppressions.append({"center": Vector2(anchor.x, anchor.z), "radius": float(spec.get("suppress_radius_m", 200.0)), "names": spec.suppress_building_names})
		if not bool(spec.get("placement_enabled", true)):
			continue
		var scene := load(str(spec.scene_path)) as PackedScene
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		add_child(model)
		model.position = anchor
		model.scale = Vector3(config.world_size_meters / ((config.bbox_east - config.bbox_west) * 111320.0 * cos(deg_to_rad(lat))), 1, config.world_size_meters / ((config.bbox_north - config.bbox_south) * 111320.0))
		_fit_terrain(model, spec, terrain)
		placements.append({"model": model, "spec": spec})
		print("[HeritageLandmarkManager] 배치: ", spec.name_ko)

func _height(local: Vector3, model: Node3D, terrain: Node3D) -> float:
	var world := model.to_global(local)
	var key := Vector2(world.x, world.z)
	if not _height_cache.has(key):
		_height_cache[key] = float(terrain.call("get_terrain_elevation", world.x, world.z))
	return _height_cache[key]

func _fit_terrain(model: Node3D, spec: Dictionary, terrain: Node3D) -> void:
	_height_cache.clear()
	var gate_floor := -INF
	if spec.has("gate"):
		for x in [-9.0, 0.0, 9.0]:
			for z in [-10.0, 0.0, 10.0]:
				gate_floor = maxf(gate_floor, _height(Vector3(spec.gate.x + x, 0, spec.gate.z + z), model, terrain))
	for child in model.get_children():
		if not child is MeshInstance3D:
			continue
		var instance := child as MeshInstance3D
		var arrays: Array = instance.mesh.surface_get_arrays(0).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var rigid_gate := str(child.name).begins_with("gate_")
		for i in range(vertices.size()):
			vertices[i].y += gate_floor if rigid_gate else _height(vertices[i], model, terrain)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var fitted := ArrayMesh.new()
		fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		instance.mesh = fitted
		# 기와의 작은 요철은 충돌에서 생략하고 성벽·기둥·마루는 충돌을 제공한다.
		if not str(child.name) in ["gate_roof", "gate_tile", "gate_green"]:
			instance.create_trimesh_collision()
	if spec.has("gate"):
		_gate_foundations(model, spec.gate, gate_floor, terrain)
	_height_cache.clear()

func _gate_foundations(model: Node3D, gate: Dictionary, floor_y: float, terrain: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		for z in [-3.2, 0.0, 3.2]:
			var p := Vector3(gate.x + x, 0, gate.z + z)
			var ground := _height(p, model, terrain)
			var depth := maxf(0.6, floor_y - ground + 0.8)
			var box := BoxMesh.new()
			box.size = Vector3(1.06, depth, 1.06)
			p.y = floor_y - depth / 2
			surface.append_from(box, 0, Transform3D(Basis.IDENTITY, p))
	var instance := MeshInstance3D.new()
	instance.name = "GateFoundations"
	instance.mesh = surface.commit()
	instance.material_override = model.get_node("gate_stone").material_override
	instance.visibility_range_end = 16000
	model.add_child(instance)
	instance.create_trimesh_collision()

func replaces_building(world_x: float, world_z: float, building_name: String = "") -> bool:
	for zone in _suppressions:
		if building_name in zone.names and Vector2(world_x, world_z).distance_to(zone.center) <= zone.radius:
			return true
	for placement in placements:
		var point: Vector3 = placement.model.to_local(Vector3(world_x, 0, world_z))
		if absf(point.x) > 240.0 or absf(point.z) > 240.0:
			continue
		var spec: Dictionary = placement.spec
		if spec.has("gate") and absf(point.x - float(spec.gate.x)) < 10.5 and absf(point.z - float(spec.gate.z)) < 12.0:
			return true
		for wall in spec.walls:
			for i in range(wall.points.size() - 1):
				var a := Vector2(wall.points[i][0], wall.points[i][1])
				var b := Vector2(wall.points[i + 1][0], wall.points[i + 1][1])
				var p := Vector2(point.x, point.z)
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < float(wall.width) * 0.5:
					return true
	return false
