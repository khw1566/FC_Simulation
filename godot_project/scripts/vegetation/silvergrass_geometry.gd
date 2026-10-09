extends RefCounted
## 잎·꽃대·이삭을 한 표면에 병합한 경량 억새·갈대 군집.
const Shapes = preload("res://scripts/vegetation/tree_geometry.gd")
## kind: [높이 m, 폭 m, 군집 중심 목록, 잎 색, 이삭 색, 잎 기울기]
const SPECS := {
	"silvergrass_clump": [1.8, 1.4, [Vector3.ZERO], Color(0.42,0.47,0.24), Color(0.86,0.82,0.70), 0.55],
	"silvergrass_patch": [1.9, 4.0, [Vector3(-1.1,0,-0.9),Vector3(0.9,0,-1.0),Vector3(0.1,0,0.1),Vector3(-1.0,0,1.0),Vector3(1.1,0,0.9)], Color(0.45,0.46,0.24), Color(0.88,0.83,0.70), 0.55],
	"reed_patch": [2.4, 3.0, [Vector3(-0.8,0,-0.6),Vector3(0.7,0,-0.7),Vector3(-0.6,0,0.7),Vector3(0.8,0,0.6)], Color(0.38,0.44,0.22), Color(0.48,0.38,0.32), 0.32],
}

static func spec(kind: String) -> Array:
	return SPECS[kind]

static func build(kind: String, lod: int) -> MeshInstance3D:
	var data: Array = SPECS[kind]
	var height: float = data[0]
	var width: float = data[1]
	var node := MeshInstance3D.new()
	node.name = kind
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if lod == 2:
		var image := Image.load_from_file("res://assets/generated/silvergrass/%s_card.png" % kind)
		image.generate_mipmaps()
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		for axis in [Vector3.RIGHT,Vector3.BACK]:
			var p := [-axis*width*0.5,axis*width*0.5,axis*width*0.5+Vector3.UP*height,-axis*width*0.5+Vector3.UP*height]
			var uv := [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
			for i in [0,1,2,0,2,3]:
				st.set_color(Color.WHITE)
				st.set_normal(Vector3.UP)
				st.set_uv(uv[i])
				st.add_vertex(p[i])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var centers: Array = data[2]
		for i in range(centers.size()):
			clump(st,centers[i],height*(1.0-float(i%3)*0.06),lod,float(i)*2.13,data[3],data[4],data[5])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.mesh = st.commit()
	node.mesh.surface_set_material(0,material)
	return node

static func clump(st: SurfaceTool, base: Vector3, height: float, lod: int, phase: float, leaf: Color, plume: Color, lean: float) -> void:
	var blades := 16 if lod == 0 else 7
	for i in range(blades):
		var angle := phase + float(i) * TAU / float(blades) + float(i % 2) * 0.3
		var outward := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-outward.z,0,outward.x)
		var length := height * (0.55 + float(i % 4) * 0.08)
		var root := base + outward * 0.08
		var middle := root + outward * length * lean * 0.45 + Vector3.UP * length * 0.62
		var tip := root + outward * length * lean + Vector3.UP * length * (0.78 - lean * 0.25)
		var color := leaf.lightened(float(i % 3) * 0.05)
		if lod == 0:
			Shapes.triangle(st,root-side*0.035,middle-side*0.02,middle+side*0.02,color)
			Shapes.triangle(st,root-side*0.035,middle+side*0.02,root+side*0.035,color)
			Shapes.triangle(st,middle-side*0.02,tip,middle+side*0.02,color)
		else:
			Shapes.triangle(st,root-side*0.04,tip,root+side*0.04,color)
	var stalks := 6 if lod == 0 else 3
	for i in range(stalks):
		var angle := phase * 1.7 + float(i) * TAU / float(stalks)
		var outward := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-outward.z,0,outward.x)
		var top := base + outward * height * 0.16 + Vector3.UP * height * (0.92 + float(i % 3) * 0.05)
		Shapes.triangle(st,base-side*0.012,top,base+side*0.012,leaf.darkened(0.1))
		var droop := top + outward * 0.22 + Vector3.DOWN * 0.38
		if lod == 0:
			for spread in [-1.0,0.0,1.0]:
				var end: Vector3 = droop + side * float(spread) * 0.10
				Shapes.triangle(st,top-side*0.035,end,top+side*0.035,plume.lightened(absf(float(spread)) * 0.06))
		else:
			Shapes.triangle(st,top-side*0.06,droop,top+side*0.06,plume)
