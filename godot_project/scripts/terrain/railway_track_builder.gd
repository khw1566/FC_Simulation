extends RefCounted
class_name RailwayTrackBuilder

static func build(points: PackedVector3Array, profile: Dictionary, structure: Dictionary, view_distance: float) -> Node3D:
	var root := Node3D.new()
	if points.size() < 2:
		return root
	root.position = points[0]
	var local := PackedVector3Array()
	for point in points:
		local.append(point - points[0])
	var slab: bool = profile.track_bed == "slab"
	var bed := _material(Color(0.57, 0.58, 0.59) if slab else Color(0.32, 0.30, 0.28))
	var steel := _material(Color(0.52, 0.55, 0.59))
	steel.metallic = 0.7
	var concrete := _material(Color(0.60, 0.59, 0.55))
	var bed_st := SurfaceTool.new()
	var rail_st := SurfaceTool.new()
	var wire_st := SurfaceTool.new()
	for surface in [bed_st, rail_st, wire_st]:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, local.size()):
		var a := local[index - 1]
		var b := local[index]
		if a.distance_to(b) < 0.01:
			continue
		_ribbon(bed_st, a, b, 3.4 if slab else 3.8, -0.14, 0.0)
		for offset in [-0.7175, 0.7175]:
			_ribbon(rail_st, a, b, 0.075, 0.12, offset)
		_ribbon(wire_st, a, b, 0.035, 5.5, 0.0)
	_add_surface(root, bed_st, bed, view_distance)
	_add_surface(root, rail_st, steel, view_distance)
	_add_surface(root, wire_st, steel, 3500.0)
	var route := preload("res://scripts/terrain/railway_route.gd").new()
	route.configure(local, [])
	var sleepers: Array[Transform3D] = []
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var supports: Array[Transform3D] = []
	var sleeper_step: float = 1.2 if slab else 0.75
	for index in range(int(route.length / sleeper_step) + 1):
		var pose: Transform3D = route.sample(index * sleeper_step)
		pose.origin += Vector3(0, 0.0, 0)
		sleepers.append(pose)
	for index in range(int(route.length / 50.0) + 1):
		var pose: Transform3D = route.sample(index * 50.0, 2.5)
		pose.origin.y += 2.7
		poles.append(pose)
		var arm: Transform3D = route.sample(index * 50.0, 1.25)
		arm.origin.y += 5.4
		arms.append(arm)
		if bool(structure.get("bridge", false)):
			var support: Transform3D = route.sample(index * 50.0)
			support.origin.y -= 4.0
			supports.append(support)
	_instances(root, Vector3(2.5, 0.16, 0.22), sleepers, concrete, 1800.0)
	_instances(root, Vector3(0.18, 5.7, 0.18), poles, steel, 5000.0)
	_instances(root, Vector3(2.7, 0.10, 0.12), arms, steel, 5000.0)
	if not supports.is_empty():
		_instances(root, Vector3(1.4, 8.0, 1.4), supports, concrete, view_distance)
	return root

static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, width: float, height: float, offset: float) -> void:
	var side := (b - a).normalized().cross(Vector3.UP).normalized()
	var left := side * (offset - width * 0.5) + Vector3.UP * height
	var right := side * (offset + width * 0.5) + Vector3.UP * height
	for vertex in [a + left, b + left, b + right, a + left, b + right, a + right]:
		st.add_vertex(vertex)

static func _add_surface(root: Node3D, st: SurfaceTool, material: Material, distance: float) -> void:
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = material
	instance.visibility_range_end = distance
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

static func _instances(root: Node3D, size: Vector3, transforms: Array[Transform3D], material: Material, distance: float) -> void:
	if transforms.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.visibility_range_end = distance
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
