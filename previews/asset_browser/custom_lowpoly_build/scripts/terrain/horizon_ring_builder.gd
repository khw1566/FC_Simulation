extends RefCounted
class_name HorizonRingBuilder

## 중앙 상세 지형을 비운 광역 DEM 링. 경사 법선과 곡률을 갖고 충돌은 생성하지 않는다.
func build(sampler: RefCounted, settings: Dictionary, terrain: Node = null) -> ArrayMesh:
	var arrays := build_arrays(sampler, settings, terrain)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func build_arrays(sampler: RefCounted, settings: Dictionary, terrain: Node = null) -> Array:
	var segments: int = settings.get("edge_segments",128)
	var rings: int = settings.get("radial_rings",16)
	var half: float = sampler.map.world_size_meters * 0.5
	var extension: float = sampler.map.extension_m
	var sea_level: float = maxf(float(sampler.map.sea_level), 0.0)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var normals := PackedVector3Array()
	var perimeter := segments*4
	var edge_heights := PackedFloat32Array()
	for i in range(perimeter):
		var unit := perimeter_point(i,segments)
		var edge_x := unit.x*(half-32.0)
		var edge_z := unit.y*(half-32.0)
		var edge: float = sampler.local_height(edge_x,edge_z)
		if settings.has("edge_heights") and settings.edge_heights.size() == perimeter:
			edge = settings.edge_heights[i]
		if terrain and terrain.has_method("get_terrain_elevation"):
			edge = terrain.get_terrain_elevation(edge_x,edge_z)
		edge_heights.append(edge)
	for ring in range(rings+1):
		var fraction := float(ring)/float(rings)
		var distance := extension*pow(fraction,1.65)
		var extent := half+distance
		if ring == 0:
			extent -= 32.0
		for i in range(perimeter):
			var unit := perimeter_point(i,segments)
			var x := unit.x*extent
			var z := unit.y*extent
			var edge: float = edge_heights[i]
			var raw: float = sampler.height(x,z)
			var blend := smoothstep(0.0, float(settings.get("seam_blend_m",6000)), distance)
			var height := lerpf(edge, raw, blend)
			if ring == 0:
				height -= 5.0
			var water: bool = height <= sea_level and not sampler.map.get("flat",false) and sampler.map.sea_level > -900.0
			if water:
				height = sea_level-0.5
			var drop := curvature(x,z,half,settings) if not sampler.map.get("flat",false) else 0.0
			height -= drop
			vertices.append(Vector3(x,height,z))
			# 원래 표고와 경계 혼합량을 셰이더로 전달한다. 색상은 가까운 지형 팔레트와 공유한다.
			colors.append(Color(maxf(height+drop,0.0)/10000.0, blend, 0.0, 1.0))
			normals.append(Vector3.UP)
	for ring in range(rings):
		for i in range(perimeter):
			var next := (i+1)%perimeter
			var a := ring*perimeter+i
			var b := ring*perimeter+next
			var c := (ring+1)*perimeter+i
			var d := (ring+1)*perimeter+next
			indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	# 실제 삼각형 면적 가중 법선. 모든 표본을 수직 법선으로 덮지 않는다.
	normals.fill(Vector3.ZERO)
	for i in range(0,indices.size(),3):
		var a: int = indices[i]
		var b: int = indices[i+1]
		var c: int = indices[i+2]
		var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		if normal.y < 0.0:
			normal = -normal
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func curvature(x: float,z: float,half: float,settings: Dictionary) -> float:
	var radius: float = settings.get("earth_radius_m",6371000.0)
	var distance := maxf(maxf(absf(x),absf(z))-half,0.0)
	var blend := smoothstep(0.0,float(settings.get("curvature_start_m",12000)),distance)
	return (radius-sqrt(maxf(radius*radius-x*x-z*z,0.0)))*blend

func perimeter_point(index: int, segments: int) -> Vector2:
	var side := index / segments
	var t := float(index % segments)/float(segments)
	match side:
		0: return Vector2(lerpf(-1,1,t), -1)
		1: return Vector2(1, lerpf(-1,1,t))
		2: return Vector2(lerpf(1,-1,t), 1)
		_: return Vector2(-1, lerpf(1,-1,t))
