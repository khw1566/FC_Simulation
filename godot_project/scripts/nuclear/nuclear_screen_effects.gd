extends CanvasLayer
class_name NuclearScreenEffects

## 섬광 백화, 화구 눈부심, 충격파 굴절 고리를 화면에 합성하고, 충격파가 관측점에 도달하면 카메라를 흔든다.
## 빛은 즉시, 충격파는 거리만큼 늦게 도착한다. 효과가 없으면 화면 복사 비용을 없애기 위해 숨긴다.

const PostShader := preload("res://shaders/nuclear/nuclear_screen_post.gdshader")
const Timeline := preload("res://scripts/nuclear/nuclear_timeline.gd")
const Locator := preload("res://scripts/nuclear/nuclear_target_locator.gd")
const MAX_ITEMS := 4
const FLASH_TINT := Color(1.0, 0.98, 0.94)

var terrain: Node
var _rect: ColorRect
var _material: ShaderMaterial
var _shake_clock := 0.0
var _shaking_camera: Camera3D

func _ready() -> void:
	# 3D 화면 위, 기존 HUD(CanvasLayer 1) 아래
	layer = -1
	_material = ShaderMaterial.new()
	_material.shader = PostShader
	_material.set_shader_parameter("flash_tint", FLASH_TINT)
	_rect = ColorRect.new()
	_rect.name = "NuclearPost"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	visible = false

func refresh(detonations: Array, camera: Camera3D, delta: float) -> void:
	if not camera or detonations.is_empty():
		visible = false
		_apply_shake(camera, 0.0, delta)
		return
	var cam_pos := camera.global_position
	var view_size := get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	var forward := -camera.global_transform.basis.z
	var shocks := _vec4_list()
	var shock_params := _vec4_list()
	var glares := _vec4_list()
	var tints := _vec4_list()
	var shock_n := 0
	var glare_n := 0
	var flash := 0.0
	var shake := 0.0
	for idx in range(detonations.size() - 1, maxi(detonations.size() - 1 - MAX_ITEMS, -1), -1):
		var d = detonations[idx]
		var tl: Timeline = d.timeline
		var fireball: Vector3 = d.get_cap_center()
		var to_fb := fireball - cam_pos
		var dist := maxf(to_fb.length(), 1.0)
		var reach := tl.light_radius * 1.5
		var falloff := reach * reach / (reach * reach + dist * dist)
		var facing := clampf(forward.dot(to_fb / dist), 0.0, 1.0)
		# 섬광은 등 뒤에서도 하늘·지면 반사로 화면을 하얗게 덮는다.
		flash = maxf(flash, tl.flash * (0.35 + 0.65 * facing) * falloff * 1.4)
		# 충격파 굴절 고리: 과압의 제곱근으로 세기를 정해 약한 원거리 전면(수십 km)도 아지랑이처럼 보이게 한다.
		if tl.shock_overpressure > 0.0015 and tl.shock_radius < 140000.0:
			var root := clampf(sqrt(tl.shock_overpressure), 0.0, 1.2)
			var fade := smoothstep(0.0015, 0.006, tl.shock_overpressure)
			var refraction := (0.006 + 0.014 * root) * fade
			shocks[shock_n] = Vector4(d.burst_point.x, d.burst_point.y, d.burst_point.z, tl.shock_radius)
			# w: 전면 껍질의 옅은 밝기 테(압축된 공기의 산란·응결)
			shock_params[shock_n] = Vector4(refraction, maxf(tl.shock_thickness * 2.5, 600.0), d.ground_point.y, clampf(root * 0.3, 0.0, 0.12) * fade)
			shock_n += 1
		var lum := (tl.flash * 3.0 + 0.6 * tl.heat * tl.heat * tl.cloud_alpha) * falloff
		if lum > 0.01 and not camera.is_position_behind(fireball) and Locator.line_clear(terrain, cam_pos, fireball, 16):
			var uv := camera.unproject_position(fireball) / view_size
			var angular := atan(maxf(tl.cap_radius, tl.fireball_radius) / dist) / maxf(tan_half, 0.01) * 0.5
			glares[glare_n] = Vector4(uv.x, uv.y, lum, clampf(angular, 0.002, 0.25))
			var tint := Timeline.heat_color(tl.heat).lerp(FLASH_TINT, clampf(tl.flash, 0.0, 1.0))
			tints[glare_n] = Vector4(tint.r, tint.g, tint.b, 1.0)
			glare_n += 1
		var since: float = d.elapsed - d.shock_arrival_at(cam_pos)
		if since >= 0.0 and since < 8.0:
			var ov := tl.blast.overpressure_ratio(cam_pos.distance_to(d.burst_point))
			shake = maxf(shake, clampf(ov * 3.0 + 0.04, 0.0, 1.0) * exp(-since / 1.4))
	_material.set_shader_parameter("cam_basis", camera.global_transform.basis)
	_material.set_shader_parameter("cam_origin", cam_pos)
	_material.set_shader_parameter("tan_half_fov", tan_half)
	_material.set_shader_parameter("aspect", view_size.x / maxf(view_size.y, 1.0))
	_material.set_shader_parameter("shock_count", shock_n)
	_material.set_shader_parameter("shock_sphere", shocks)
	_material.set_shader_parameter("shock_params", shock_params)
	_material.set_shader_parameter("glare_count", glare_n)
	_material.set_shader_parameter("glare", glares)
	_material.set_shader_parameter("glare_tint", tints)
	_material.set_shader_parameter("flash_amount", minf(flash, 0.95))
	visible = flash > 0.002 or shock_n > 0 or glare_n > 0
	_apply_shake(camera, shake, delta)

## 충격파 통과 진동: 플레이어가 쓰지 않는 카메라 롤·요 축만 흔든다.
func _apply_shake(camera: Camera3D, amount: float, delta: float) -> void:
	if amount <= 0.001:
		if _shaking_camera and is_instance_valid(_shaking_camera):
			_shaking_camera.rotation.z = 0.0
			_shaking_camera.rotation.y = 0.0
		_shaking_camera = null
		return
	_shaking_camera = camera
	_shake_clock += delta
	var t := _shake_clock
	camera.rotation.z = (sin(t * 47.0) + sin(t * 31.0 + 1.3)) * 0.5 * amount * 0.014
	camera.rotation.y = sin(t * 39.0 + 0.7) * amount * 0.008

static func _vec4_list() -> PackedVector4Array:
	var list := PackedVector4Array()
	list.resize(MAX_ITEMS)
	return list
