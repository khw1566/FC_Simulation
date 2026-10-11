extends RefCounted
class_name BridgeGeometry

## 재질별로 합쳐지는 교량 부재. 노드 수가 케이블/난간 개수에 비례하지 않는다.
var batches: Dictionary = {}

func beam(a: Vector3, b: Vector3, width: float, depth: float, group: String = "structure") -> void:
	var delta := b - a
	if delta.length() < 0.001:
		return
	var up := delta.normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.1:
		side = up.cross(Vector3.RIGHT).normalized()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, delta.length(), depth)
	if not batches.has(group):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[group] = surface
	var transform := Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	batches[group].append_from(mesh, 0, transform)

func finish(parent: Node3D) -> void:
	var colors := {"deck": Color(0.23, 0.24, 0.25), "structure": Color(0.72, 0.73, 0.72), "cable": Color(0.83, 0.84, 0.84), "stone": Color(0.48, 0.47, 0.43)}
	for group in batches:
		var instance := MeshInstance3D.new()
		instance.name = str(group)
		instance.mesh = batches[group].commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = colors.get(group, Color.GRAY)
		material.roughness = 0.85
		instance.material_override = material
		instance.visibility_range_end = 18000.0
		parent.add_child(instance)
		if group == "deck" or group == "stone":
			instance.create_trimesh_collision()
