extends RefCounted
## 한 재질과 정점 색상으로 경량 나무를 생성한다.
static func build(kind: String, lod: int, height: float, width: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = kind
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if lod == 2:
		var image := Image.load_from_file("res://assets/generated/trees/%s_card.png" % kind)
		image.generate_mipmaps()
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			var points := [-axis * width / 2.0, axis * width / 2.0, axis * width / 2.0 + Vector3.UP * height, -axis * width / 2.0 + Vector3.UP * height]
			var uvs := [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
			for index in [0,1,2,0,2,3]:
				surface.set_color(Color.WHITE)
				surface.set_normal(Vector3.UP)
				surface.set_uv(uvs[index])
				surface.add_vertex(points[index])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var trunk := Color(0.24, 0.16, 0.09) if kind != "slender" else Color(0.63, 0.61, 0.52)
		var green := Color(0.20, 0.36, 0.13) if kind != "conifer" else Color(0.10, 0.27, 0.16)
		var segments := 6 if lod == 0 else 3
		cone(surface, Vector3.ZERO, height * 0.64, width * 0.055, width * 0.03, segments, trunk)
		if kind == "conifer":
			for level in range(3 if lod == 0 else 2):
				cone(surface, Vector3(0, height * (0.18 + level * 0.22), 0), height * 0.38, width * (0.5 - level * 0.12), 0, 8 if lod == 0 else 4, green.lightened(level * 0.035))
		else:
			var crown_y := height * (0.65 if kind != "shrub" else 0.53)
			var crown_h := height * (0.35 if kind != "shrub" else 0.46)
			ellipsoid(surface, Vector3(0,crown_y,0), Vector3(width * 0.5,crown_h,width * 0.44), 8 if lod == 0 else 4, 4 if lod == 0 else 2, green)
			if lod == 0 and kind == "broadleaf":
				for side in [-1,1]:
					ellipsoid(surface, Vector3(side * width * 0.24,height * 0.53,0), Vector3(width * 0.28,height * 0.24,width * 0.32), 6, 3, green.darkened(0.07))
			if lod == 0 and kind == "slender":
				cone(surface, Vector3(0,height*0.45,0), height*0.18,width*0.15,0.02,4,trunk)
		material.cull_mode = BaseMaterial3D.CULL_BACK
	node.mesh = surface.commit()
	node.mesh.surface_set_material(0, material)
	return node

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	if normal.length_squared() < 0.01:
		return
	st.set_color(color)
	st.set_normal(normal)
	for p in [a,b,c]:
		st.add_vertex(p)

static func cone(st: SurfaceTool, base: Vector3, height: float, radius: float, top: float, segments: int, color: Color) -> void:
	for i in range(segments):
		var a := TAU * i / segments
		var b := TAU * (i+1) / segments
		var p := base + Vector3(cos(a)*radius,0,sin(a)*radius)
		var q := base + Vector3(cos(b)*radius,0,sin(b)*radius)
		var r := base + Vector3(cos(a)*top,height,sin(a)*top)
		var s := base + Vector3(cos(b)*top,height,sin(b)*top)
		triangle(st,p,r,s,color)
		triangle(st,p,s,q,color)
		triangle(st,base,p,q,color)
		if top > 0:
			triangle(st,base+Vector3.UP*height,s,r,color)

static func ellipsoid(st: SurfaceTool, center: Vector3, scale_value: Vector3, segments: int, rings: int, color: Color) -> void:
	for ring in range(rings):
		for i in range(segments):
			var points: Array[Vector3] = []
			for uv in [Vector2(i,ring),Vector2(i+1,ring),Vector2(i+1,ring+1),Vector2(i,ring+1)]:
				var angle: float = uv.x * TAU / segments
				var latitude: float = uv.y * PI / rings
				points.append(center + Vector3(sin(latitude)*cos(angle),cos(latitude),sin(latitude)*sin(angle)) * scale_value)
			triangle(st,points[0],points[1],points[2],color)
			triangle(st,points[0],points[2],points[3],color)
