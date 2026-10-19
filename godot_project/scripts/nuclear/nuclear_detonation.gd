extends Node3D
class_name NuclearDetonation

## 핵폭발 한 건의 수명 주기: 경과 시간에 따라 화구·버섯구름·지면 먼지·충격파 먼지 띠·윌슨 응결운·섬광 광원을 갱신하고,
## 바람장에 대류 교란(상승류·유입풍·유출)을 더하며, 기존 구름 상호작용과 화면 효과가 읽을 상태를 제공한다.

signal finished(detonation: Node)

const Timeline := preload("res://scripts/nuclear/nuclear_timeline.gd")
const Factory := preload("res://scripts/nuclear/nuclear_visual_factory.gd")
const Probe := preload("res://scripts/nuclear/nuclear_environment_probe.gd")
const WindPerturbationScript := preload("res://scripts/nuclear/nuclear_wind_perturbation.gd")
const AFTERWIND_SPEED := 25.0
const STEM_LEVELS := 8
const WIND_EVENT_INTERVAL := 0.25

var preset: Dictionary
var timeline: Timeline
var probe: Probe
var elapsed := 0.0
var ground_point := Vector3.ZERO
var burst_point := Vector3.ZERO
var over_water := false
var humidity_ground := 0.6
var humidity_high := 0.4

var _drift := Vector3.ZERO
var _inflow := 0.0
var _decks: Array = []
var _stem_offsets := PackedVector2Array()
var _volume_mat: ShaderMaterial
var _wilson: MeshInstance3D
var _wilson_mat: ShaderMaterial
var _light: OmniLight3D
var _wind_event_id := -1
var _wind_event_timer := 0.0

func setup(preset_data: Dictionary, ground: Vector3, convection_scale: float, env_probe: Probe, water: bool) -> void:
	preset = preset_data
	timeline = Timeline.new(preset_data, convection_scale)
	ground_point = ground
	burst_point = ground + Vector3.UP * timeline.burst_height
	probe = env_probe
	over_water = water
	humidity_ground = probe.humidity_at(ground.y + 50.0)
	humidity_high = probe.humidity_at(ground.y + 5000.0)
	_decks = probe.cloud_decks()
	_stem_offsets.resize(STEM_LEVELS)
	name = "Detonation_%s" % str(preset_data.id)

func _ready() -> void:
	_volume_mat = Factory.create_mushroom(self).material_override as ShaderMaterial
	_wilson = Factory.create_wilson_shell(self)
	_wilson_mat = _wilson.material_override as ShaderMaterial
	_light = Factory.create_flash_light(self)
	Factory.apply_quality(_volume_mat, probe.render_quality())
	_volume_mat.set_shader_parameter("water_burst", 1.0 if over_water else 0.0)
	# 수면 폭발의 기저 서지와 충격파 띠는 흙먼지 대신 물보라다.
	_volume_mat.set_shader_parameter("dust_color", Color(0.86, 0.88, 0.9) if over_water else Color(0.62, 0.55, 0.46))
	var field: Node = probe.wind_field
	if field and field.has_method("register_perturbation"):
		_wind_event_id = field.register_perturbation(WindPerturbationScript.new(), _wind_params())
	advance(0.0)

func _exit_tree() -> void:
	var field: Node = probe.wind_field if probe else null
	if _wind_event_id >= 0 and field and is_instance_valid(field):
		field.remove_perturbation(_wind_event_id)
	_wind_event_id = -1

## 관리자가 매 프레임 호출한다(구름 상호작용·화면 효과와 같은 프레임 상태를 쓰기 위해 자체 _process를 두지 않는다).
func advance(delta: float) -> void:
	elapsed += delta
	timeline.evaluate(elapsed)
	var dtc := delta * timeline.convection_scale
	# 갓은 그 위치·고도의 바람장에 떠밀리고, 지면에서는 후폭풍이 먼지를 폭심으로 끌어들인다.
	var cap_wind := probe.wind_at(get_cap_center())
	_drift += Vector3(cap_wind.x, 0.0, cap_wind.z) * dtc * smoothstep(0.02, 0.2, timeline.age_ratio)
	_inflow += dtc * AFTERWIND_SPEED * (1.0 - smoothstep(1.0, 3.0, timeline.age_ratio))
	_advance_stem_shear(dtc)
	_wind_event_timer += delta
	if _wind_event_id >= 0 and _wind_event_timer >= WIND_EVENT_INTERVAL:
		_wind_event_timer = 0.0
		probe.wind_field.update_perturbation(_wind_event_id, _wind_params())
	_update_volume()
	_update_wilson()
	_update_light()
	if timeline.is_finished():
		finished.emit(self)
		queue_free()

## 그리기 칸(0 = 가장 먼 폭발). 관리자가 카메라 거리순으로 정한다.
func set_render_slot(slot: int) -> void:
	if _volume_mat and _wilson_mat:
		Factory.assign_slot(_volume_mat, _wilson_mat, slot)

func get_cap_center() -> Vector3:
	return Vector3(ground_point.x + _drift.x, ground_point.y + timeline.cap_height, ground_point.z + _drift.z)

## 카메라 등 지점에 충격파가 도달하는 경과 시각(s)
func shock_arrival_at(point: Vector3) -> float:
	return timeline.blast.arrival_time(point.distance_to(burst_point))

## 기존 구름층 셰이더의 blast_a~f 한 행
func cloud_uniform_row() -> Array:
	var tl := timeline
	var cap := get_cap_center()
	var alpha := tl.cloud_alpha
	var heat_col := Timeline.heat_color(tl.heat)
	var stem_formed := clampf(tl.stem_top / maxf(tl.cap_height, 1.0), 0.0, 1.0)
	return [
		Vector4(ground_point.x, ground_point.y, ground_point.z, tl.shock_radius),
		Vector4(cap.x, cap.y, cap.z, tl.cap_radius * alpha),
		Vector4(tl.flash * 12.0, tl.light_radius, 3.0 * tl.heat * tl.heat * alpha, tl.shock_overpressure),
		Vector4(tl.stem_radius * alpha * stem_formed, tl.cap_half_height * alpha, tl.clear_radius * alpha, tl.shock_thickness),
		Vector4(heat_col.r, heat_col.g, heat_col.b, burst_point.y),
		Vector4(tl.surge_radius if tl.surge_alpha > 0.05 else 0.0, tl.surge_height, ground_point.y + tl.stem_top, 0.0),
	]

## 바람장에 더할 대류 교란 값(작업 스레드로 복사되므로 값만 담는다)
func _wind_params() -> Dictionary:
	var tl := timeline
	return {
		"ground": ground_point,
		"cap": get_cap_center(),
		"cap_radius": tl.cap_radius,
		"cap_half": tl.cap_half_height,
		"stem_radius": tl.stem_radius,
		"updraft": clampf(tl.rise_speed * 1.5, 10.0, 80.0),
		"strength": smoothstep(0.0, 0.05, tl.age_ratio) * (1.0 - smoothstep(1.5, 3.5, tl.age_ratio)) * tl.cloud_alpha,
	}

## 기둥 높이별 수평 변위: 각 고도의 바람에 밀리되, 아래에서 올라오는 새 먼지로 체류 시간만큼만 기운다.
## 정상 상태 변위 = 그 고도 바람 × 체류 시간(높이 / 상승 속도)이라 위로 갈수록 바람 방향으로 굽는다.
func _advance_stem_shear(dtc: float) -> void:
	var tl := timeline
	var level_height := _stem_level_height()
	for i in range(1, STEM_LEVELS):
		var h := level_height * float(i) / float(STEM_LEVELS - 1)
		if h > tl.stem_top:
			break
		var off := _stem_offsets[i]
		var wind := probe.wind_at(Vector3(ground_point.x + off.x, ground_point.y + h, ground_point.z + off.y))
		var residence := clampf(h / maxf(tl.rise_speed * 0.5, 5.0), 10.0, 900.0)
		off += (Vector2(wind.x, wind.z) - off / residence) * dtc
		_stem_offsets[i] = off

func _stem_level_height() -> float:
	return maxf(timeline.cap_height - timeline.cap_half_height * 0.5, 10.0)

func _apply_environment(material: ShaderMaterial) -> void:
	var tl := timeline
	material.set_shader_parameter("sun_direction", probe.sun_direction)
	material.set_shader_parameter("sun_color", _vec3(probe.sun_color))
	material.set_shader_parameter("ambient_color", _vec3(probe.ambient))
	material.set_shader_parameter("haze_color", _vec3(probe.haze_color))
	material.set_shader_parameter("haze_density", probe.haze_density)
	material.set_shader_parameter("anim_time", tl.cloud_time)
	material.set_shader_parameter("fireball_position", get_cap_center())
	material.set_shader_parameter("heat", tl.heat)
	material.set_shader_parameter("glow_strength", tl.flash * 25.0 + 2.5 * tl.heat * tl.heat)
	material.set_shader_parameter("glow_radius", tl.cap_radius * 3.0 + tl.fireball_max * 2.0)

func _update_volume() -> void:
	var tl := timeline
	var m := _volume_mat
	_apply_environment(m)
	m.set_shader_parameter("extinction", 7.0 / maxf(tl.cap_radius, 40.0))
	m.set_shader_parameter("stem_extinction", 4.5 / maxf(tl.stem_radius, 20.0))
	m.set_shader_parameter("burst_origin", ground_point)
	m.set_shader_parameter("ground_height", ground_point.y)
	m.set_shader_parameter("cap_center", get_cap_center())
	m.set_shader_parameter("cap_radius", maxf(tl.cap_radius, 1.0))
	m.set_shader_parameter("cap_half_height", maxf(tl.cap_half_height, 1.0))
	m.set_shader_parameter("form", tl.form)
	m.set_shader_parameter("roll_phase", tl.roll_phase)
	# 섬광 중에는 눈부신 백색, 이후에는 냉각 색(황→주황→적)이 보이도록 밝기를 낮춘다.
	var lum := (1.0 + 30.0 * tl.flash * tl.flash + 2.0 * tl.heat * tl.heat) * smoothstep(0.02, 0.1, tl.heat)
	m.set_shader_parameter("luminosity", lum)
	m.set_shader_parameter("stem_radius", tl.stem_radius)
	m.set_shader_parameter("stem_top", ground_point.y + tl.stem_top)
	m.set_shader_parameter("stem_rise_speed", maxf(tl.rise_speed * 0.6, 8.0))
	m.set_shader_parameter("stem_offsets", _stem_offsets)
	m.set_shader_parameter("stem_level_height", _stem_level_height())
	m.set_shader_parameter("pileus_alpha", tl.pileus_alpha * smoothstep(0.35, 0.8, humidity_high))
	m.set_shader_parameter("collar_a", _collar(0))
	m.set_shader_parameter("collar_b", _collar(1))
	m.set_shader_parameter("cloud_alpha", tl.cloud_alpha)
	m.set_shader_parameter("debris_age", tl.age_ratio)
	var surge_h := maxf(tl.surge_height, 10.0)
	m.set_shader_parameter("surge_radius", maxf(tl.surge_radius, 1.0))
	m.set_shader_parameter("surge_height", surge_h)
	m.set_shader_parameter("surge_alpha", tl.surge_alpha)
	m.set_shader_parameter("surge_extinction", 2.0 / maxf(surge_h, 50.0))
	m.set_shader_parameter("inflow_offset", _inflow)
	m.set_shader_parameter("shock_radius", tl.shock_radius)
	m.set_shader_parameter("shock_width", maxf(tl.shock_thickness * 2.5, 150.0))
	m.set_shader_parameter("shock_strength", _shock_ground_strength())

## 지형을 쓸고 가는 충격파 먼지 띠 세기: 과압의 제곱근을 써 수십 km 밖까지 남긴다.
func _shock_ground_strength() -> float:
	var tl := timeline
	var k := clampf(sqrt(maxf(tl.shock_overpressure, 0.0)) * 2.5, 0.0, 1.0)
	return k * smoothstep(tl.fireball_max, tl.fireball_max * 2.0, tl.shock_radius) * (1.0 - smoothstep(100000.0, 140000.0, tl.shock_radius))

## 기둥이 관통한 기존 구름 덮개 고도의 응결 고리
func _collar(index: int) -> Vector4:
	if index >= _decks.size():
		return Vector4.ZERO
	var deck: Vector3 = _decks[index]
	return Vector4(deck.x, deck.y, deck.z * _collar_strength(), 0.0)

func _collar_strength() -> float:
	return timeline.collar_alpha * clampf(0.4 + humidity_ground, 0.0, 1.2)

func _update_wilson() -> void:
	var tl := timeline
	var moisture := clampf(0.25 + 1.2 * (humidity_ground - 0.45) + (0.3 if over_water else 0.0), 0.15, 1.0)
	var alpha := tl.wilson_alpha * moisture
	_wilson.visible = alpha > 0.002 and tl.wilson_radius > 1.0
	if not _wilson.visible:
		return
	_wilson.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * tl.wilson_radius), burst_point)
	var lit := probe.ambient + probe.sun_color * 0.8 + Color(1.0, 0.97, 0.92) * tl.flash * 4.0
	_wilson_mat.set_shader_parameter("shell_center", burst_point)
	_wilson_mat.set_shader_parameter("shell_radius", tl.wilson_radius)
	_wilson_mat.set_shader_parameter("ground_height", ground_point.y)
	_wilson_mat.set_shader_parameter("shell_alpha", alpha)
	_wilson_mat.set_shader_parameter("shell_color", _vec3(lit * Color(0.92, 0.94, 0.97)))
	_wilson_mat.set_shader_parameter("anim_time", elapsed)

func _update_light() -> void:
	var tl := timeline
	var root := sqrt(tl.light_radius)
	var energy := tl.flash * 3.0 * root + 0.4 * root * tl.heat * tl.heat * tl.cloud_alpha
	_light.visible = energy > 0.05
	if not _light.visible:
		return
	_light.global_position = get_cap_center()
	_light.light_color = Timeline.heat_color(tl.heat).lerp(Color(1.0, 0.98, 0.95), clampf(tl.flash, 0.0, 1.0))
	_light.light_energy = energy
	_light.omni_range = minf(tl.light_radius * 2.5, 60000.0)

static func _vec3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
