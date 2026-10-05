extends RefCounted
class_name IndustrialPlacementBuilder

## 설비 발판을 표시 지표에 연결하고 상세·원경 변환을 일치시킨다.
static func pose(entry: Dictionary, terrain: Node3D) -> Transform3D:
	var p: Array = entry.position
	var basis := Basis(Vector3.UP,deg_to_rad(float(entry.yaw_degrees))).scaled(Vector3.ONE*float(entry.scale))
	var location := Vector3(p[0],p[1],p[2])
	if is_instance_valid(terrain):
		var highest := -INF
		var lo: Array = entry.aabb_min_m
		var hi: Array = entry.aabb_max_m
		for x in [lo[0],hi[0]]:
			for z in [lo[2],hi[2]]:
				var world: Vector3 = location+basis*Vector3(x,0,z)
				highest = maxf(highest,ground(terrain,world.x,world.z))
		location.y = highest+0.12-float(lo[1])*float(entry.scale)
	return Transform3D(basis,location)

static func ground(terrain: Node3D,x: float,z: float) -> float:
	return float(terrain.get_rendered_terrain_elevation(x,z)) if terrain.has_method("get_rendered_terrain_elevation") else float(terrain.get_terrain_elevation(x,z))

static func foundation(model: Node3D,entry: Dictionary,terrain: Node3D) -> void:
	var node := model.get_node_or_null("IndustrialFoundation") as MeshInstance3D
	if not node:
		node = MeshInstance3D.new()
		node.name = "IndustrialFoundation"
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.40,0.40,0.38)
		node.material_override = material
		model.add_child(node)
	var lo: Array = entry.aabb_min_m
	var hi: Array = entry.aabb_max_m
	var lowest := float(entry.foundation_bottom_y)
	if is_instance_valid(terrain):
		lowest = INF
		for x in [lo[0],hi[0]]:
			for z in [lo[2],hi[2]]:
				var point: Vector3 = model.transform*Vector3(x,0,z)
				lowest = minf(lowest,ground(terrain,point.x,point.z)-0.75)
	var bottom := (lowest-model.position.y)/float(entry.scale)
	var top := float(lo[1])
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(hi[0])-float(lo[0]),maxf(0.25,top-bottom),float(hi[2])-float(lo[2]))
	node.mesh = mesh
	node.position = Vector3((float(lo[0])+float(hi[0]))*0.5,top-mesh.size.y*0.5,(float(lo[2])+float(hi[2]))*0.5)
	var body := node.get_node_or_null("FoundationBody") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "FoundationBody"
		node.add_child(body)
		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		body.add_child(collision)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	body.get_node("Shape").shape = shape
