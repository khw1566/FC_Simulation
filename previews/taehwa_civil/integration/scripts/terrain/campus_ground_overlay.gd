extends RefCounted
class_name CampusGroundOverlay

## 현재 지형을 따라가는 영상 표면. 실측 지형을 새로 생성하지 않는다.
static func build(parent: Node3D, sample: Callable, step: float = 10.0, origin: float = -850.0) -> void:
	var path := "res://assets/maps/ulsan_uc_west/campus_imagery.png"
	if not FileAccess.file_exists(path):
		return
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ix0 := int(ceil((-850.0-origin)/step))
	var iz0 := ix0
	for iz in range(iz0,int(floor((850.0-origin)/step))):
		for ix in range(ix0,int(floor((650.0-origin)/step))):
			var x := origin + ix * step
			var z := origin + iz * step
			for p in [Vector2(x,z),Vector2(x+step,z),Vector2(x,z+step),Vector2(x+step,z),Vector2(x+step,z+step),Vector2(x,z+step)]:
				surface.set_uv(Vector2((p.x+850)/1500.0,(p.y+850)/1700.0))
				surface.add_vertex(Vector3(p.x,float(sample.call(p.x,p.y,0))+0.16,p.y))
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.albedo_color = Color(0.85,0.85,0.85)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new()
	mesh.name = "Campus_ImageryGround"
	mesh.mesh = surface.commit()
	mesh.material_override = material
	parent.add_child(mesh)
