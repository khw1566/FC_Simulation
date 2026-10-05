extends RefCounted
class_name IndustrialRoadBuilder

const Road = preload("res://scripts/terrain/road_mesh_builder.gd")

static func build(roads: Array, placements: Array, terrain: Node3D) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := Vector2.ZERO
	var origin := Vector2.ZERO
	if is_instance_valid(terrain):
		step = Vector2(terrain.terrain_world_size/terrain.grid_chunks_x/128.0,terrain.terrain_world_size/terrain.grid_chunks_y/128.0)
		origin = Vector2.ONE*-terrain.terrain_world_size*0.5
	var entries := roads.duplicate()
	for placement in placements:
		entries.append({"points_xz":placement.driveway_xz,"width_m":6.0})
	for entry in entries:
		var points: Array[Vector3] = []
		var heights: Array[float] = []
		for p in entry.points_xz:
			var y: float = terrain.get_terrain_elevation(p[0],p[1]) if terrain else 0.0
			points.append(Vector3(p[0],y,p[1]))
			heights.append(y)
		var sampler := func(x: float,z: float,fallback: float) -> float:
			return terrain.get_terrain_elevation(x,z) if terrain else fallback
		Road.build_surface_road(surface,points,heights,float(entry.width_m),sampler,step,origin)
	var node := MeshInstance3D.new()
	node.name = "IndustrialRoads"
	node.mesh = surface.commit()
	node.material_override = terrain.create_road_material() if terrain else null
	node.visibility_range_end = 11000.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
