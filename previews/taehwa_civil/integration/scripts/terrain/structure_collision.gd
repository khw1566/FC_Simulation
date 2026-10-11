extends RefCounted
class_name StructureCollision

## 교량 등 고정 구조물의 메시에서 충돌체를 만든다. 이미 충돌체가 있는 메시는 건너뛴다.
static func add_trimesh(root: Node) -> void:
	if root is MeshInstance3D and root.mesh != null and not _has_body(root):
		root.create_trimesh_collision()
	for child in root.get_children():
		if not child is CollisionObject3D:
			add_trimesh(child)

static func _has_body(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject3D:
			return true
	return false
