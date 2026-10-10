extends RefCounted

## 같은 씬을 여러 번 놓을 때 씬 안의 메시마다 MultiMeshInstance3D로 묶는다.
## 넓은 범위를 한 덩어리로 묶으면 컬링이 안 되므로 격자 칸마다 따로 만든다.

const CELL_M := 400.0
const VISIBILITY_END_M := 3000.0
const VISIBILITY_MARGIN_M := 300.0

## template: 인스턴스화한 원본 씬(호출 후 해제하지 않는다). transforms: 월드 변환 배열.
static func build(parent: Node3D, name_prefix: String, template: Node3D, transforms: Array) -> int:
	var parts: Array = []
	_collect_meshes(template, Transform3D.IDENTITY, parts)
	if parts.is_empty():
		return 0
	var cells: Dictionary = {}
	for xform in transforms:
		var key := Vector2i(floori(xform.origin.x / CELL_M), floori(xform.origin.z / CELL_M))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xform)
	var made := 0
	for key in cells:
		var cell_transforms: Array = cells[key]
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = part.mesh
			multimesh.instance_count = cell_transforms.size()
			# 가시 거리는 노드 원점 기준이므로 노드를 칸 중심에 두고 인스턴스 변환을 칸 기준으로 옮긴다
			var center := Vector3((key.x + 0.5) * CELL_M, 0.0, (key.y + 0.5) * CELL_M)
			for i in range(cell_transforms.size()):
				var world: Transform3D = cell_transforms[i] * part.local
				world.origin -= center
				multimesh.set_instance_transform(i, world)
			var instance := MultiMeshInstance3D.new()
			instance.position = center
			instance.name = "%s_%d_%d_%d" % [name_prefix, key.x, key.y, part_index]
			instance.multimesh = multimesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = VISIBILITY_END_M
			instance.visibility_range_end_margin = VISIBILITY_MARGIN_M
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(instance)
			made += 1
	return made

static func _collect_meshes(node: Node, accumulated: Transform3D, parts: Array) -> void:
	var local := accumulated
	if node is Node3D:
		local = accumulated * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		parts.append({"mesh": (node as MeshInstance3D).mesh, "local": local})
	for child in node.get_children():
		_collect_meshes(child, local, parts)
