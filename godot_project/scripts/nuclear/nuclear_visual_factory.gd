extends RefCounted
class_name NuclearVisualFactory

## 핵폭발 한 건의 시각 노드(버섯구름·지면 먼지 통합 볼륨, 윌슨 응결 껍질, 섬광 광원)와 공유 잡음 텍스처를 만든다.
## 그리기 순서: 폭발마다 [볼륨, 응결 껍질] 두 칸을 MIN + 1 ~ MIN + 8에 배정하고(먼 폭발부터),
## 기존 구름층(MIN + 9)이 맨 나중에 앞쪽 구름만 덮는다. 같은 우선순위를 공유하면 정렬이 흔들려 깜박인다.

const MushroomShader := preload("res://shaders/nuclear/nuclear_mushroom_volume.gdshader")
const WilsonShader := preload("res://shaders/nuclear/nuclear_wilson_shell.gdshader")
const RenderOrderScript := preload("res://scripts/core/render_order.gd")
const VOLUME_PRIORITY := RenderOrderScript.NUCLEAR_FIRST
# 품질별 [통합 볼륨 표본, 태양 그림자 표본]
const QUALITY_STEPS := [[88, 3], [72, 2], [52, 2], [36, 1]]

static var _shape_noise: NoiseTexture3D
static var _detail_noise: NoiseTexture3D

static func create_mushroom(parent: Node3D) -> MeshInstance3D:
	return _create_volume(parent, "MushroomCloudVolume", MushroomShader)

static func create_wilson_shell(parent: Node3D) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = WilsonShader
	material.render_priority = VOLUME_PRIORITY
	material.set_shader_parameter("shape_noise", shape_noise())
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var node := MeshInstance3D.new()
	node.name = "WilsonCondensationShell"
	node.mesh = sphere
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.top_level = true
	node.visible = false
	parent.add_child(node)
	return node

static func create_flash_light(parent: Node3D) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "FireballLight"
	light.shadow_enabled = false
	# 완만한 감쇠로 수십 km 밖 지형까지 섬광이 닿게 한다.
	light.omni_attenuation = 0.5
	light.light_specular = 0.2
	light.top_level = true
	light.visible = false
	parent.add_child(light)
	return light

static func apply_quality(volume: ShaderMaterial, quality: int) -> void:
	var q: Array = QUALITY_STEPS[clampi(quality, 0, QUALITY_STEPS.size() - 1)]
	volume.set_shader_parameter("step_count", int(q[0]))
	volume.set_shader_parameter("light_steps", int(q[1]))

## 거리순 그리기 칸(0 = 가장 먼 폭발) 배정
static func assign_slot(volume: ShaderMaterial, shell: ShaderMaterial, slot: int) -> void:
	var order := RenderOrderScript.nuclear_slot(slot)
	volume.render_priority = order.x
	shell.render_priority = order.y

static func shape_noise() -> NoiseTexture3D:
	if not _shape_noise:
		_shape_noise = _noise_3d(64, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 4, 77213)
	return _shape_noise

static func detail_noise() -> NoiseTexture3D:
	if not _detail_noise:
		_detail_noise = _noise_3d(32, FastNoiseLite.TYPE_CELLULAR, 0.12, 3, 50311)
	return _detail_noise

static func _create_volume(parent: Node3D, label: String, shader: Shader) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = VOLUME_PRIORITY
	material.set_shader_parameter("compatibility_depth", RenderingServer.get_rendering_device() == null)
	material.set_shader_parameter("shape_noise", shape_noise())
	material.set_shader_parameter("detail_noise", detail_noise())
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	# 정점 셰이더가 화면에 고정하므로 컬링되지 않게 경계를 크게 잡는다.
	quad.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.ignore_occlusion_culling = true
	node.extra_cull_margin = 16384.0
	parent.add_child(node)
	return node

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
