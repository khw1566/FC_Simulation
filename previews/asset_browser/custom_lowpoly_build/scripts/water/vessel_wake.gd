extends MeshInstance3D
class_name VesselWake

## 선미가 지나간 세계 좌표를 보존하는 유한 길이의 거품 항적.
const FOAM_SHADER = preload("res://shaders/vessel_wake.gdshader")
var _samples: Array = []
var _clock := 0.0
var _accumulator := 0.0
var _length := 20.0
var _beam := 5.0
var _lifetime := 30.0
var _last_position := Vector3.ZERO
var _has_position := false

func configure(entry: Dictionary, settings: Dictionary) -> void:
	_length = float(entry.length_m)
	_beam = float(entry.beam_m)
	_lifetime = clampf(_length * 0.22 + 12.0, 15.0, float(settings.get("wake_max_lifetime_seconds", 65.0)))
	var material := ShaderMaterial.new()
	material.shader = FOAM_SHADER
	material.render_priority = 2
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func advance(delta: float, pose: Transform3D, speed: float) -> void:
	_clock += delta
	_accumulator += delta
	while not _samples.is_empty() and _clock - float(_samples[0].time) > _lifetime:
		_samples.pop_front()
	if _accumulator < 0.35:
		return
	_accumulator = 0.0
	var stern := pose.origin + pose.basis.z * _length * 0.48
	stern.y = pose.origin.y + 0.24
	if speed > 0.15:
		# 정박 후 재출항이나 표시 범위 재진입을 긴 선으로 연결하지 않는다.
		if _has_position and stern.distance_to(_last_position) > maxf(50.0, speed * 2.0):
			_samples.clear()
		if not _has_position or stern.distance_to(_last_position) > 0.3:
			_samples.append({"position": stern, "time": _clock, "strength": clampf(speed / 6.0, 0.18, 1.0), "side": pose.basis.x})
			_last_position = stern
			_has_position = true
	else:
		_has_position = false
	while _samples.size() > 192:
		_samples.pop_front()
	_rebuild()

func _rebuild() -> void:
	if _samples.size() < 2:
		mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(_samples.size() - 1):
		var a: Dictionary = _samples[index]
		var b: Dictionary = _samples[index + 1]
		# 정박 기간을 가로지르는 항적은 연결하지 않는다.
		if float(b.time) - float(a.time) > 1.5:
			continue
		var direction: Vector3 = (b.position - a.position).normalized()
		var side := direction.cross(Vector3.UP).normalized()
		var age_a := clampf((_clock - float(a.time)) / _lifetime, 0.0, 1.0)
		var age_b := clampf((_clock - float(b.time)) / _lifetime, 0.0, 1.0)
		var width_a := _beam * (0.32 + age_a * 1.8)
		var width_b := _beam * (0.32 + age_b * 1.8)
		var positions: Array[Vector3] = [a.position - side * width_a, a.position + side * width_a, b.position - side * width_b, b.position + side * width_b]
		var opacity_a := pow(1.0 - age_a, 1.5) * float(a.strength)
		var opacity_b := pow(1.0 - age_b, 1.5) * float(b.strength)
		for vertex in [0, 2, 1, 1, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(1, 1, 1, opacity_a if vertex < 2 else opacity_b))
			surface.set_uv(Vector2(float(vertex % 2), float(a.time if vertex < 2 else b.time) * 0.8))
			surface.add_vertex(positions[vertex])
	mesh = surface.commit()
