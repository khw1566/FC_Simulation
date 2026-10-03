extends Node3D
class_name TerrainChunk

signal chunk_loaded(chunk_coord: Vector2i)

var chunk_coord: Vector2i
var chunk_world_size: float
var chunk_center: Vector3
var current_lod: int = -1
var _lod_mesh_cache: Dictionary = {}

var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

var heightmap_image: Image
var elev_min: float
var elev_max: float

# LOD 레벨별 버텍스 그리드 해상도 (2의 거듭제곱) - 노트북/데스크탑 최적화
const LOD_RESOLUTIONS: Dictionary = {
	0: 128, # 근거리 고해상도 (타일당 128x128 버텍스)
	1: 64,  # 중거리 (타일당 64x64 버텍스)
	2: 32   # 원거리 (타일당 32x32 버텍스)
}

func init_chunk(coord: Vector2i, size: float, center_pos: Vector3, img: Image, min_h: float, max_h: float) -> void:
	chunk_coord = coord
	chunk_world_size = size
	chunk_center = center_pos
	position = center_pos
	heightmap_image = img
	elev_min = min_h
	elev_max = max_h

func update_lod(target_lod: int, shader_mat: Material) -> void:
	if current_lod == target_lod:
		return

	current_lod = target_lod
	_rebuild_mesh(shader_mat)

func _rebuild_mesh(shader_mat: Material) -> void:
	if not LOD_RESOLUTIONS.has(current_lod):
		# 범위 밖 (너무 먼 거리)일 경우 메쉬 제거
		if mesh_instance:
			mesh_instance.visible = false
		if collision_shape:
			collision_shape.disabled = true
		return

	if _lod_mesh_cache.has(current_lod):
		mesh_instance.mesh = _lod_mesh_cache[current_lod]
		mesh_instance.visible = true
		if collision_shape:
			collision_shape.disabled = current_lod != 0
		return

	var grid_res: int = LOD_RESOLUTIONS[current_lod]
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step := chunk_world_size / float(grid_res)
	var half_size := chunk_world_size * 0.5
	var elev_range := elev_max - elev_min

	var img_w := heightmap_image.get_width()
	var img_h := heightmap_image.get_height()

	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()

	for y in range(grid_res + 1):
		var v := float(y) / float(grid_res)

		for x in range(grid_res + 1):
			var u := float(x) / float(grid_res)
			var norm_h := _sample_bilinear(u, v, img_w, img_h)
			var local_y := elev_min + norm_h * elev_range
			var local_x := (float(x) * step) - half_size
			var local_z := (float(y) * step) - half_size

			vertices.append(Vector3(local_x, local_y, local_z))
			uvs.append(Vector2(u, v))

	for y in range(grid_res):
		for x in range(grid_res):
			var i0 := y * (grid_res + 1) + x
			var i1 := i0 + 1
			var i2 := (y + 1) * (grid_res + 1) + x
			var i3 := i2 + 1

			surface_tool.set_uv(uvs[i0])
			surface_tool.add_vertex(vertices[i0])
			surface_tool.set_uv(uvs[i1])
			surface_tool.add_vertex(vertices[i1])
			surface_tool.set_uv(uvs[i2])
			surface_tool.add_vertex(vertices[i2])

			surface_tool.set_uv(uvs[i1])
			surface_tool.add_vertex(vertices[i1])
			surface_tool.set_uv(uvs[i3])
			surface_tool.add_vertex(vertices[i3])
			surface_tool.set_uv(uvs[i2])
			surface_tool.add_vertex(vertices[i2])

	surface_tool.generate_normals()
	var new_mesh := surface_tool.commit()
	_lod_mesh_cache[current_lod] = new_mesh

	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh"
		add_child(mesh_instance)

	mesh_instance.mesh = new_mesh
	mesh_instance.material_override = shader_mat
	mesh_instance.visible = true

	# LOD 0(최근접 청크)에서만 정밀 물리 충돌체 생성/유지하여 버벅임(BVH 재구축 스파이크) 원천 제거
	if current_lod == 0:
		if not collision_body:
			collision_body = StaticBody3D.new()
			collision_shape = CollisionShape3D.new()
			collision_body.add_child(collision_shape)
			add_child(collision_body)

		if collision_shape.shape == null:
			collision_shape.shape = new_mesh.create_trimesh_shape()
		collision_shape.disabled = false
	else:
		if collision_shape:
			collision_shape.disabled = true

# 높이맵 픽셀 계단현상(Aliasing / Blockiness) 방지를 위한 3차 에르미트(Smoothstep Cubic) 보간 함수
func _sample_bilinear(u: float, v: float, w: int, h: int) -> float:
	var fx: float = clampf(u * float(w - 1), 0.0, float(w - 1))
	var fy: float = clampf(v * float(h - 1), 0.0, float(h - 1))

	var x0: int = int(fx)
	var y0: int = int(fy)
	var x1: int = mini(x0 + 1, w - 1)
	var y1: int = mini(y0 + 1, h - 1)

	var raw_dx: float = fx - float(x0)
	var raw_dy: float = fy - float(y0)

	# 3차 에르미트 S-커브 (smoothstep) 가중치로 픽셀 격자 경계의 꺾임 제거
	var dx: float = raw_dx * raw_dx * (3.0 - 2.0 * raw_dx)
	var dy: float = raw_dy * raw_dy * (3.0 - 2.0 * raw_dy)

	var h00: float = heightmap_image.get_pixel(x0, y0).r
	var h10: float = heightmap_image.get_pixel(x1, y0).r
	var h01: float = heightmap_image.get_pixel(x0, y1).r
	var h11: float = heightmap_image.get_pixel(x1, y1).r

	var h_top: float = lerpf(h00, h10, dx)
	var h_bot: float = lerpf(h01, h11, dx)
	return lerpf(h_top, h_bot, dy)
