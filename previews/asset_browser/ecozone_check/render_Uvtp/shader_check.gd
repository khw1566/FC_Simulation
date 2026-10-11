extends SceneTree
func _initialize() -> void:
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/procedural_terrain.gdshader")
	mat.set_shader_parameter("simple_contour_mode", true)
	m.material_override = mat
	root.add_child(m)
	var cam := Camera3D.new()
	cam.position = Vector3(0,0,3)
	root.add_child(cam)
	await process_frame
	await process_frame
	print("SHADER OK uniforms=", mat.shader.get_shader_uniform_list().size())
	quit(0)
