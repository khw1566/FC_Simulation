extends Node3D
class_name OpticalEffectsController

## 기존 구름의 동일 밀도장·바람·주야간·안개 설정을 두 광학 패스로 전달한다.
const ShadowShader = preload("res://shaders/optics/cloud_ground_shadow.gdshader")
const LightShader = preload("res://shaders/optics/atmospheric_light.gdshader")
const SHARED := ["weather_noise", "base_noise", "detail_noise", "wind_offset", "cirrus_offset",
	"cirrus_wind_dir", "evolve", "cu_coverage", "cu_base", "cu_top", "st_coverage", "st_base",
	"st_top", "cb_coverage", "cb_base", "cb_top", "as_coverage", "as_base", "as_top",
	"ci_coverage", "ci_altitude", "slab_bottom", "slab_top", "detail_distance", "extinction",
	"sun_direction", "sun_color", "haze_density"]
const RAY_STEPS := [8, 6, 4, 2]
@export_range(0.0, 1.0) var cloud_shadow_strength := 0.32
@export_range(0.0, 2.0) var ray_strength := 0.75
@export_range(0.0, 2.0) var flare_strength := 0.34
@export var lens_flare_enabled := true
@export var light_rays_enabled := true
@export var cloud_shadows_enabled := true
var _cloud: Node3D
var _shadow: MeshInstance3D
var _light: MeshInstance3D
var _shadow_material: ShaderMaterial
var _light_material: ShaderMaterial
var _idle_sync := 0.0

func _ready() -> void:
	_cloud = get_parent()
	_shadow = _make_pass("CloudGroundShadow", ShadowShader, -128)
	_light = _make_pass("AtmosphericLight", LightShader, -126)
	_shadow_material = _shadow.material_override as ShaderMaterial
	_light_material = _light.material_override as ShaderMaterial

func _make_pass(label: String, shader: Shader, priority: int) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	material.set_shader_parameter("compatibility_depth", RenderingServer.get_rendering_device() == null)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mesh.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.ignore_occlusion_culling = true
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node

func _process(delta: float) -> void:
	# 맑음 상태에서 구름 레이마칭은 멈춰도 태양·안개 동기화는 계속한다.
	_idle_sync += delta
	if _idle_sync >= 0.25 and _cloud and not _cloud.is_processing():
		_cloud._sync_environment()
		_idle_sync = 0.0
	var camera := get_viewport().get_camera_3d()
	if not camera or not _cloud or not _cloud._material:
		_shadow.visible = false
		_light.visible = false
		return
	var source: ShaderMaterial = _cloud._material
	var quality := clampi(int(_cloud._current_quality), 0, 3)
	var active := bool(_cloud._is_active) and int(_cloud._current_quality) < 4
	var has_clouds: bool = active and _cloud._ratios.length_squared() > 0.000001
	var direction: Vector3 = source.get_shader_parameter("sun_direction")
	var weather: Node = _cloud.get_parent()
	var sun: DirectionalLight3D = weather.get("sun_light") as DirectionalLight3D
	# 야간에는 방향광이 달을 향한다. 태양 광학 효과는 주야간 가중치로 별도 차단한다.
	var daylight := 1.0 - float(_cloud._get_night_weight())
	var sunlit := sun != null and sun.visible and daylight > 0.01 and direction.y > 0.015
	_shadow.visible = has_clouds and sunlit and cloud_shadows_enabled and sun.shadow_enabled
	_light.visible = sunlit and (lens_flare_enabled or (has_clouds and light_rays_enabled))
	for material in [_shadow_material, _light_material]:
		for key in SHARED:
			if key == "sun_color" and material == _shadow_material:
				continue
			material.set_shader_parameter(key, source.get_shader_parameter(key))
		material.set_shader_parameter("clouds_active", has_clouds)
	_shadow_material.set_shader_parameter("shadow_strength", cloud_shadow_strength * daylight)
	_light_material.set_shader_parameter("ray_strength", ray_strength * daylight if light_rays_enabled else 0.0)
	_light_material.set_shader_parameter("ray_steps", RAY_STEPS[quality])
	_light_material.set_shader_parameter("flare_strength", flare_strength)
	var sun_position := camera.global_position + direction * 20000.0
	var uv := camera.unproject_position(sun_position) / get_viewport().get_visible_rect().size
	var in_view := not camera.is_position_behind(sun_position) and Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv)
	_light_material.set_shader_parameter("sun_uv", uv)
	_light_material.set_shader_parameter("flare_visibility", daylight if lens_flare_enabled and in_view else 0.0)
