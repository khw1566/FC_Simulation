extends RefCounted
## 유형별 풀과 공유 노이즈를 한 번 생성한다.

static func create(parent: Node3D, radius: float) -> Array[Dictionary]:
	var noise := FastNoiseLite.new()
	noise.seed = 29471
	noise.frequency = 0.075
	noise.fractal_octaves = 3
	var texture := NoiseTexture3D.new()
	texture.width = 48
	texture.height = 32
	texture.depth = 48
	texture.seamless = true
	texture.noise = noise
	var shader := preload("res://shaders/procedural_cloud_volume.gdshader")
	var compatibility_depth: bool = RenderingServer.get_rendering_device() == null
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var rng := RandomNumberGenerator.new()
	rng.seed = 73291
	var specs := [
		["Cumulus", 6, Vector3(1800, 700, 1500), 1100.0, 1700.0, 12.0],
		["Stratus", 4, Vector3(6200, 450, 5400), 1700.0, 2300.0, 9.0],
		["Cirrus", 4, Vector3(6400, 200, 2300), 6500.0, 8500.0, 3.5],
		["Cumulonimbus", 2, Vector3(3800, 3800, 3400), 2900.0, 3500.0, 15.0]
	]
	var pool: Array[Dictionary] = []
	for kind in range(specs.size()):
		var spec: Array = specs[kind]
		for i in range(int(spec[1])):
			var node := MeshInstance3D.new()
			node.name = "%s_%02d" % [spec[0], i]
			node.mesh = box
			node.scale = spec[2] * rng.randf_range(0.85, 1.15)
			var angle := float(i) * 2.399963 + float(kind) * 1.2
			var distance := radius * sqrt((float(i) + 0.4) / float(spec[1])) * 0.75
			node.position = Vector3(cos(angle) * distance, rng.randf_range(spec[3], spec[4]), sin(angle) * distance)
			node.rotation.y = 0.4 + rng.randf_range(-0.2, 0.2) if kind == 2 else rng.randf_range(0.0, TAU)
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("compatibility_depth", compatibility_depth)
			material.set_shader_parameter("shape_noise", texture)
			material.set_shader_parameter("cloud_type", kind)
			material.set_shader_parameter("cloud_density", spec[5])
			material.set_shader_parameter("noise_offset", Vector3(rng.randf(), rng.randf(), rng.randf()))
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visible = false
			parent.add_child(node)
			pool.append({"node": node, "material": material, "kind": kind, "index": i})
	return pool
