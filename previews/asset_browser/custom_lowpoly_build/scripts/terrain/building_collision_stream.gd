extends RefCounted
class_name BuildingCollisionStream

## 플레이어 주변 건물 청크에만 충돌체를 만들고 멀어지면 해제한다.
## 전 지역 건물에 충돌체를 두면 생성 비용과 메모리가 커지므로 반경과 프레임당 생성 수를 제한한다.
const COLLISION_META := "building_collision"
# 1,500m 건물 청크 기준으로 플레이어 주변 최소 약 1.2km를 덮는다.
var create_radius := 2250.0
var release_radius := 2750.0
var max_builds_per_update := 1

## chunks: { key: {"node": Node3D, "center_2d": Vector2} }
func update(chunks: Dictionary, player_2d: Vector2) -> void:
	var pending: Array = []
	for key in chunks.keys():
		var info: Dictionary = chunks[key]
		var node: Node3D = info.get("node")
		if not is_instance_valid(node):
			continue
		var distance := player_2d.distance_to(info.get("center_2d", Vector2.ZERO))
		var has_collision := node.has_meta(COLLISION_META)
		if has_collision and distance > release_radius:
			_release(node)
		elif not has_collision and distance <= create_radius:
			pending.append({"node": node, "distance": distance})
	pending.sort_custom(func(a, b): return a.distance < b.distance)
	for index in mini(max_builds_per_update, pending.size()):
		_build(pending[index].node)

func _build(chunk_node: Node3D) -> void:
	chunk_node.set_meta(COLLISION_META, true)
	for container in chunk_node.get_children():
		for child in container.get_children():
			if child is MeshInstance3D and child.mesh != null:
				var body := StaticBody3D.new()
				body.name = "BuildingCollision"
				var shape := CollisionShape3D.new()
				shape.shape = child.mesh.create_trimesh_shape()
				body.add_child(shape)
				child.add_child(body)

func _release(chunk_node: Node3D) -> void:
	chunk_node.remove_meta(COLLISION_META)
	for container in chunk_node.get_children():
		for child in container.get_children():
			var body := child.get_node_or_null("BuildingCollision")
			if body:
				body.queue_free()
