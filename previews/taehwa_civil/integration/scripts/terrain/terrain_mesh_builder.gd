extends Node3D
class_name TerrainMeshBuilder

@export var heightmap_texture: Texture2D
@export var min_elevation: float = -50.0
@export var max_elevation: float = 650.0
@export var terrain_world_size: float = 18000.0 # 18km
@export var grid_resolution: int = 256 # 256x256 grid vertices

func _ready() -> void:
	build_terrain_mesh()

func build_terrain_mesh() -> void:
	var img: Image = null
	if heightmap_texture:
		img = heightmap_texture.get_image()
	else:
		var raw_path = "res://assets/generated/kanmon_heightmap_16bit.png"
		if FileAccess.file_exists(raw_path):
			img = Image.load_from_file(raw_path)
			
	if not img:
		push_error("Heightmap image could not be loaded.")
		return

	img.convert(Image.FORMAT_RF) # 32-bit Float Grayscale로 변환
	var img_w: int = img.get_width()
	var img_h: int = img.get_height()

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step := terrain_world_size / float(grid_resolution)
	var half_size := terrain_world_size * 0.5
	var elev_range := max_elevation - min_elevation

	# 버텍스 배열 임시 버퍼 생성
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()

	for y in range(grid_resolution + 1):
		var v := float(y) / float(grid_resolution)
		var samp_y: int = clampi(int(v * float(img_h - 1)), 0, img_h - 1)

		for x in range(grid_resolution + 1):
			var u := float(x) / float(grid_resolution)
			var samp_x: int = clampi(int(u * float(img_w - 1)), 0, img_w - 1)

			var norm_h := img.get_pixel(samp_x, samp_y).r
			var world_y := min_elevation + norm_h * elev_range
			var world_x := (float(x) * step) - half_size
			var world_z := (float(y) * step) - half_size

			vertices.append(Vector3(world_x, world_y, world_z))
			uvs.append(Vector2(u, v))

	# 인덱스 생성
	for y in range(grid_resolution):
		for x in range(grid_resolution):
			var i0 := y * (grid_resolution + 1) + x
			var i1 := i0 + 1
			var i2 := (y + 1) * (grid_resolution + 1) + x
			var i3 := i2 + 1

			# 삼각형 1 (상방 노멀: i0 -> i1 -> i2)
			surface_tool.set_uv(uvs[i0])
			surface_tool.add_vertex(vertices[i0])
			surface_tool.set_uv(uvs[i1])
			surface_tool.add_vertex(vertices[i1])
			surface_tool.set_uv(uvs[i2])
			surface_tool.add_vertex(vertices[i2])

			# 삼각형 2 (상방 노멀: i1 -> i3 -> i2)
			surface_tool.set_uv(uvs[i1])
			surface_tool.add_vertex(vertices[i1])
			surface_tool.set_uv(uvs[i3])
			surface_tool.add_vertex(vertices[i3])
			surface_tool.set_uv(uvs[i2])
			surface_tool.add_vertex(vertices[i2])

	surface_tool.generate_normals()
	var mesh := surface_tool.commit()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.name = "TerrainMeshInstance"

	# 셰이더 머티리얼 적용
	var shader = load("res://shaders/procedural_terrain.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("min_height", min_elevation)
		mat.set_shader_parameter("max_height", max_elevation)
		mesh_instance.material_override = mat

	add_child(mesh_instance)

	# 지형 충돌체 생성
	var col_shape := mesh.create_trimesh_shape()
	if col_shape:
		var static_body := StaticBody3D.new()
		var col_instance := CollisionShape3D.new()
		col_instance.shape = col_shape
		static_body.add_child(col_instance)
		add_child(static_body)

	print("[TerrainMeshBuilder] Generated 3D terrain mesh successfully with ", vertices.size(), " vertices.")
