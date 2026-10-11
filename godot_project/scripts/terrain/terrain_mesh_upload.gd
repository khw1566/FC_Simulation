extends RefCounted
class_name TerrainMeshUpload

## 완성된 지형을 공유 프레임 예산 안에서 업로드하고, 교체가 끝날 때까지 숨긴다.
const Budget = preload("res://scripts/terrain/stream_frame_budget.gd")
const SURFACES_PER_MESH := 64
var container: Node3D
var meshes: Array[MeshInstance3D] = []
var _pages: Array = []
var _cursor := 0
var _mesh: ArrayMesh
var _material: Material

func begin(owner: Node, pages: Array, material: Material) -> void:
	_pages = pages
	_material = material
	container = Node3D.new()
	container.name = "TerrainLOD"
	container.visible = false
	owner.add_child(container)

func step(immediate: bool = false) -> bool:
	while _cursor<_pages.size():
		if not immediate and not Budget.can_submit():
			return false
		var started := Time.get_ticks_usec()
		if _mesh==null or _mesh.get_surface_count()>=SURFACES_PER_MESH:
			_mesh = ArrayMesh.new()
			var instance := MeshInstance3D.new()
			instance.mesh = _mesh
			instance.material_override = _material
			container.add_child(instance)
			meshes.append(instance)
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_pages[_cursor])
		_pages[_cursor] = null
		_cursor += 1
		if not immediate:
			Budget.record(started)
	_pages.clear()
	return true
