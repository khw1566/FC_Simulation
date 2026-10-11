extends RefCounted
## 줄기·마디·잎을 한 표면에 병합한 경량 대나무.
const Shapes = preload("res://scripts/vegetation/tree_geometry.gd")
static func placements(kind: String) -> Array[Vector3]:
	if kind == "bamboo_single":
		return [Vector3.ZERO]
	if kind == "bamboo_clump":
		return [Vector3(-0.6,0,-0.3),Vector3(0.55,0,-0.15),Vector3(-0.25,0,0.7),Vector3(0.65,0,0.65)]
	return [Vector3(-2.8,0,-2.7),Vector3(0.2,0,-2.8),Vector3(2.7,0,-2.4),Vector3(-2.5,0,0.2),Vector3(0,0,0),Vector3(2.6,0,0.4),Vector3(-2.7,0,2.7),Vector3(0.3,0,2.5),Vector3(2.9,0,2.8)]

static func build(kind: String, lod: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = kind
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if lod == 2:
		var image := Image.load_from_file("res://assets/generated/bamboo/%s_card.png" % kind)
		image.generate_mipmaps()
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		var width: float = {"bamboo_single":3.0,"bamboo_clump":4.5,"bamboo_grove":9.0}[kind]
		for axis in [Vector3.RIGHT,Vector3.BACK]:
			var p := [-axis*width*0.5,axis*width*0.5,axis*width*0.5+Vector3.UP*9.0,-axis*width*0.5+Vector3.UP*9.0]
			var uv := [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
			for i in [0,1,2,0,2,3]:
				st.set_color(Color.WHITE)
				st.set_normal(Vector3.UP)
				st.set_uv(uv[i])
				st.add_vertex(p[i])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var points := placements(kind)
		for i in range(points.size()):
			var height := 9.0 * (1.0 - float(i%4)*0.055)
			stalk(st,points[i],height,lod,float(i)*1.71)
	node.mesh = st.commit()
	node.mesh.surface_set_material(0,material)
	return node

static func stalk(st: SurfaceTool, base: Vector3, height: float, lod: int, phase: float) -> void:
	var stem := Color(0.32,0.43,0.12)
	Shapes.cone(st,base,height,0.075,0.045,4 if lod == 0 else 3,stem)
	if lod == 0:
		for fraction in [0.24,0.45,0.66]:
			Shapes.cone(st,base+Vector3.UP*height*fraction,0.045,0.082,0.082,4,Color(0.22,0.31,0.075))
	for i in range(4 if lod == 0 else 2):
		var fraction := 0.48 + float(i) * (0.11 if lod == 0 else 0.23)
		var center := base+Vector3.UP*height*fraction
		var angle := phase + float(i)*2.4
		var direction := Vector3(cos(angle),0.16,sin(angle))
		var tip := center+direction*1.0
		var side := Vector3(-direction.z,0,direction.x)
		Shapes.triangle(st,center-side*0.015,tip,center+side*0.015,stem)
		Shapes.triangle(st,center+side*0.015,tip+side*0.015,tip,stem)
		for anchor in ([0.3,0.6] if lod == 0 else [0.4]):
			for sign_value in [-1.0,1.0]:
				var start := center+direction*float(anchor)
				var end: Vector3 = tip + side*sign_value*0.55 + Vector3.UP*0.15
				var middle: Vector3 = (start+end)*0.5
				var leaf_width := direction*0.20
				var color := Color(0.16,0.32,0.09).lightened(float(i%2)*0.05)
				Shapes.triangle(st,start,middle-leaf_width,end,color)
				Shapes.triangle(st,start,end,middle+leaf_width,color)
