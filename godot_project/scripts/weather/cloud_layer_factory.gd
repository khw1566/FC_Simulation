extends RefCounted
## 화면 전체 구름층 패스(쿼드 1개)와 공유 노이즈 텍스처를 한 번 생성한다.

const SHADER := preload("res://shaders/sky_cloud_layer.gdshader")
const RenderOrderScript := preload("res://scripts/core/render_order.gd")

static func create(parent: Node3D) -> Dictionary:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	# 앞쪽 구간 패스: 핵폭발 볼륨 뒤에 그려 버섯구름보다 가까운 구름만 그 위에 덮는다(순서는 RenderOrder).
	material.render_priority = RenderOrderScript.CLOUD_FRONT
	material.set_shader_parameter("blast_split_mode", 0)
	material.set_shader_parameter("compatibility_depth", RenderingServer.get_rendering_device() == null)
	material.set_shader_parameter("weather_noise", _weather_texture())
	material.set_shader_parameter("base_noise", _noise_3d(64, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 4, 41873))
	material.set_shader_parameter("detail_noise", _noise_3d(32, FastNoiseLite.TYPE_CELLULAR, 0.12, 3, 90517))

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	# 정점 셰이더가 화면에 고정하므로 컬링되지 않게 경계를 크게 잡는다.
	quad.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))

	var node := MeshInstance3D.new()
	node.name = "SkyCloudLayer"
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.ignore_occlusion_culling = true
	node.extra_cull_margin = 16384.0
	node.visible = false
	parent.add_child(node)
	return {"node": node, "material": material}

## 뒤쪽 구간 패스: 앞쪽 패스와 같은 셰이더·텍스처를 공유하고, 핵폭발 볼륨보다 먼저 그려
## 버섯구름보다 먼 구름을 미리 깐다. 유니폼은 구름 관리자가 매 프레임 앞쪽 패스에서 복사한다.
static func create_behind(parent: Node3D, front: Dictionary) -> Dictionary:
	var source: ShaderMaterial = front.material
	var material := source.duplicate() as ShaderMaterial
	material.render_priority = RenderOrderScript.CLOUD_BEHIND
	material.set_shader_parameter("blast_split_mode", 1)
	var front_node: MeshInstance3D = front.node
	var node := MeshInstance3D.new()
	node.name = "SkyCloudLayerBehind"
	node.mesh = front_node.mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.ignore_occlusion_culling = true
	node.extra_cull_margin = 16384.0
	node.visible = false
	parent.add_child(node)
	return {"node": node, "material": material}

## 기상도용 2D 노이즈: 셰이더가 여러 배율(6.5km~42km)로 재표본한다.
static func _weather_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 18341
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture

static func _noise_3d(size: int, type: int, frequency: float, octaves: int, seed_value: int) -> NoiseTexture3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = type
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	if type == FastNoiseLite.TYPE_CELLULAR:
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var texture := NoiseTexture3D.new()
	texture.width = size
	texture.height = size
	texture.depth = size
	texture.seamless = true
	texture.noise = noise
	return texture
