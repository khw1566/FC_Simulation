extends RefCounted
class_name CampusArchitectureBuilder

## 실측이 아닌 캠퍼스 외관 보강. 원본 건물 윤곽을 유지한다.
static func build(parent: Node3D, polygon: PackedVector2Array, base: float, roof: float, sample: Callable) -> void:
	var batches: Dictionary = {"windows": [], "stone": [], "roof": []}
	var expanded := Geometry2D.offset_polygon(polygon, 3.0)
	for ring in expanded:
		_add_pad(parent, ring, base + 0.06, sample)
	for i in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var direction := (b - a).normalized()
		var outward := Vector2(-direction.y, direction.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + outward * 0.2, polygon):
			outward = -outward
		var length := a.distance_to(b)
		var angle := -atan2(direction.y, direction.x)
		var midpoint := (a + b) * 0.5 + outward * 0.12
		_box(batches.stone, Vector3(midpoint.x, roof + 0.35, midpoint.y), Vector3(length, 0.7, 0.24), angle)
		for floor_index in range(maxi(1, int((roof - base) / 3.6))):
			var y := base + 1.8 + floor_index * 3.6
			if y + 0.85 > roof - 0.4:
				continue
			for column in range(1, int(length / 3.2)):
				var p := a + direction * (column * 3.2) + outward * 0.08
				_box(batches.windows, Vector3(p.x, y, p.y), Vector3(1.8, 1.65, 0.12), angle)
		if i == 0 and length > 10.0:
			var p := (a + b) * 0.5 + outward * 1.6
			_box(batches.stone, Vector3(p.x, base + 3.2, p.y), Vector3(6, 0.25, 3.2), angle)
			for step in range(6):
				p = (a + b) * 0.5 + outward * (3.2 + step * 0.4)
				_box(batches.stone, Vector3(p.x, base - step * 0.18, p.y), Vector3(5, 0.22, 0.42), angle)
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	var center := bounds.get_center()
	# 모든 옥상 설비 꼭짓점이 건물 윤곽 내부에 있을 때만 배치한다.
	var fits := true
	for offset in [Vector2(-2,-1.5), Vector2(2,-1.5), Vector2(2,1.5), Vector2(-2,1.5)]:
		fits = fits and Geometry2D.is_point_in_polygon(center + offset, polygon)
	if fits:
		_box(batches.roof, Vector3(center.x, roof + 0.75, center.y), Vector3(4, 1.5, 3), 0)
	for kind in batches:
		_commit_boxes(parent, kind, batches[kind])

static func _box(batch: Array, position: Vector3, size: Vector3, angle: float) -> void:
	batch.append(Transform3D(Basis(Vector3.UP, angle) * Basis.from_scale(size), position))

static func _commit_boxes(parent: Node3D, kind: String, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = {"windows": Color(0.16,0.23,0.27), "stone": Color(0.67,0.65,0.61), "roof": Color(0.36,0.38,0.39)}[kind]
	material.roughness = 0.85
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Campus_" + kind
	instance.multimesh = multimesh
	parent.add_child(instance)

static func _add_pad(parent: Node3D, ring: PackedVector2Array, y: float, sample: Callable) -> void:
	var indices := Geometry2D.triangulate_polygon(ring)
	if indices.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		surface.add_vertex(Vector3(ring[index].x, y, ring[index].y))
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i+1) % ring.size()]
		var low_a := minf(y - 0.2, float(sample.call(a.x,a.y,y)) - 0.15)
		var low_b := minf(y - 0.2, float(sample.call(b.x,b.y,y)) - 0.15)
		for v in [Vector3(a.x,y,a.y),Vector3(b.x,y,b.y),Vector3(b.x,low_b,b.y),Vector3(a.x,y,a.y),Vector3(b.x,low_b,b.y),Vector3(a.x,low_a,a.y)]:
			surface.add_vertex(v)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48,0.47,0.44)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.name = "Campus_PadAndRetainingWall"
	instance.mesh = surface.commit()
	instance.material_override = material
	parent.add_child(instance)
	instance.create_trimesh_collision()
