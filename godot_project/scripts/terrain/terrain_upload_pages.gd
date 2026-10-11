extends RefCounted
class_name TerrainUploadPages

## 큰 지형 배열만 작업 스레드에서 분할한다. 삼각형 형상은 보존한다.
const TRIANGLES := 16000
const DIRECT_TRIANGLES := 48000

static func split(arrays: Array) -> Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.size()<=DIRECT_TRIANGLES*3:
		return [arrays]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var pages: Array = []
	for first in range(0,indices.size(),TRIANGLES*3):
		var remap: Dictionary = {}
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var uv := PackedVector2Array()
		var order := PackedInt32Array()
		for offset in range(first,mini(first+TRIANGLES*3,indices.size())):
			var original := indices[offset]
			if not remap.has(original):
				remap[original] = v.size()
				v.append(vertices[original])
				n.append(normals[original])
				uv.append(uvs[original])
			order.append(remap[original])
		var page: Array = []
		page.resize(Mesh.ARRAY_MAX)
		page[Mesh.ARRAY_VERTEX] = v
		page[Mesh.ARRAY_NORMAL] = n
		page[Mesh.ARRAY_TEX_UV] = uv
		page[Mesh.ARRAY_INDEX] = order
		pages.append(page)
	return pages
