extends Node3D
class_name NuclearExplosionManager

## 핵폭발 시뮬레이션 오케스트레이터: 위력 선택, 조준·투하, 폭발 생성(동시 최대 4건),
## 기존 구름 상호작용·화면 효과·HUD를 같은 프레임 상태로 갱신한다.

const Catalog := preload("res://scripts/nuclear/nuclear_yield_catalog.gd")
const Probe := preload("res://scripts/nuclear/nuclear_environment_probe.gd")
const Detonation := preload("res://scripts/nuclear/nuclear_detonation.gd")
const Bomb := preload("res://scripts/nuclear/nuclear_bomb_body.gd")
const Locator := preload("res://scripts/nuclear/nuclear_target_locator.gd")
const Factory := preload("res://scripts/nuclear/nuclear_visual_factory.gd")
const Interaction := preload("res://scripts/nuclear/nuclear_cloud_interaction.gd")
const ScreenEffects := preload("res://scripts/nuclear/nuclear_screen_effects.gd")
const HudView := preload("res://scripts/views/nuclear_strike_hud_view.gd")
const Controller := preload("res://scripts/controllers/nuclear_strike_controller.gd")
const MAX_ACTIVE := 4
const HUD_INTERVAL := 0.1

@export var player_node: Node3D
@export var terrain_manager: Node
@export var weather_manager: Node
@export var cloud_manager: Node3D
@export var sun_light: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var day_night_service: Node
## 3차원 바람장. 폭발마다 대류 교란을 등록해 주변 바람과 구름을 바꾼다.
@export var wind_field: Node
## 부력 대류(구름 상승·확산) 배속. 1이면 실제 속도(안정화 4~10분). 섬광·화구 냉각·충격파는 항상 실시간이다.
@export_range(0.25, 20.0) var convection_time_scale := 3.0
## 폭발 고도 위 투하 시작 높이(m)와 초기 낙하 속도(m/s)
@export var drop_height := 1500.0
@export var drop_speed := 150.0

var selected_index := 0
var _probe: Probe
var _interaction: Interaction
var _screen: ScreenEffects
var _hud: HudView
var _detonations: Array = []
var _bombs: Array = []
var _hud_timer := 0.0

func _ready() -> void:
	_resolve_references()
	_probe = Probe.new()
	_probe.sun_light = sun_light
	_probe.world_environment = world_environment
	_probe.weather_manager = weather_manager
	_probe.cloud_manager = cloud_manager
	_probe.day_night_service = day_night_service
	_probe.wind_field = wind_field
	# 첫 폭발 때 끊기지 않도록 공유 잡음을 미리 만든다.
	Factory.shape_noise()
	Factory.detail_noise()
	_interaction = Interaction.new()
	_interaction.name = "NuclearCloudInteraction"
	_interaction.cloud_manager = cloud_manager
	add_child(_interaction)
	_screen = ScreenEffects.new()
	_screen.name = "NuclearScreenEffects"
	_screen.terrain = terrain_manager
	add_child(_screen)
	_hud = HudView.new()
	_hud.name = "NuclearStrikeHUD"
	add_child(_hud)
	var controller := Controller.new()
	controller.name = "NuclearStrikeController"
	controller.manager = self
	controller.player_node = player_node
	add_child(controller)
	_refresh_hud()

func cycle_yield() -> void:
	selected_index = (selected_index + 1) % Catalog.count()
	_refresh_hud()

## 카메라 조준점(지형 교차점, 하늘이면 위력별 기본 거리) 상공에서 선택 위력 폭탄을 투하한다.
func drop_selected() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var preset := Catalog.get_preset(selected_index)
	var target := Locator.locate(camera, terrain_manager, float(preset.standoff))
	var burst_y := target.y + Catalog.burst_height(float(preset.kilotons))
	var bomb := Bomb.new()
	bomb.setup(preset, target, burst_y, drop_height, drop_speed)
	bomb.reached_burst_height.connect(_on_bomb_burst)
	add_child(bomb)
	_bombs.append(bomb)
	_refresh_hud()

func detonate(preset: Dictionary, ground: Vector3) -> void:
	if _detonations.size() >= MAX_ACTIVE:
		var oldest: Node = _detonations.pop_front()
		oldest.queue_free()
	_probe.refresh()
	var detonation := Detonation.new()
	detonation.setup(preset, ground, convection_time_scale, _probe, Locator.is_water(terrain_manager, ground))
	detonation.finished.connect(_on_detonation_finished)
	add_child(detonation)
	_detonations.append(detonation)

func clear_all() -> void:
	for bomb in _bombs:
		if is_instance_valid(bomb):
			bomb.queue_free()
	for detonation in _detonations:
		if is_instance_valid(detonation):
			detonation.queue_free()
	_bombs.clear()
	_detonations.clear()
	_interaction.push(_detonations)
	_screen.refresh(_detonations, get_viewport().get_camera_3d(), 0.0)
	_refresh_hud()

func get_active_detonations() -> Array:
	return _detonations.duplicate()

func _process(delta: float) -> void:
	if _detonations.is_empty() and _bombs.is_empty():
		_interaction.push(_detonations)
		return
	_probe.refresh()
	for detonation in _detonations.duplicate():
		detonation.advance(delta)
	_assign_render_slots()
	_interaction.push(_detonations)
	_screen.refresh(_detonations, get_viewport().get_camera_3d(), delta)
	_hud_timer += delta
	if _hud_timer >= HUD_INTERVAL:
		_hud_timer = 0.0
		_refresh_hud()

## 겹친 폭발이 같은 우선순위로 정렬 순서가 흔들려 깜박이지 않도록, 먼 폭발부터 고정 칸을 배정한다.
func _assign_render_slots() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or _detonations.is_empty():
		return
	var eye := camera.global_position
	var ordered := _detonations.duplicate()
	ordered.sort_custom(func(a: Node, b: Node) -> bool:
		return eye.distance_squared_to(a.burst_point) > eye.distance_squared_to(b.burst_point))
	for slot in range(ordered.size()):
		ordered[slot].set_render_slot(slot)

func _on_bomb_burst(bomb: Node) -> void:
	_bombs.erase(bomb)
	detonate(bomb.preset, bomb.ground_point)

func _on_detonation_finished(detonation: Node) -> void:
	_detonations.erase(detonation)

func _refresh_hud() -> void:
	if not _hud:
		return
	var preset := Catalog.get_preset(selected_index)
	var lines: Array[String] = ["[핵폭발]  B 위력: %s   V 조준점 투하   K 전체 제거" % str(preset.label)]
	for bomb in _bombs:
		if is_instance_valid(bomb):
			lines.append("투하 중 %s  폭발까지 %.1f초" % [str(bomb.preset.label), bomb.time_to_burst()])
	var camera := get_viewport().get_camera_3d()
	for i in range(_detonations.size() - 1, -1, -1):
		lines.append(_describe(_detonations[i], camera))
	_hud.show_status("\n".join(PackedStringArray(lines)))

func _describe(detonation: Node, camera: Camera3D) -> String:
	var tl = detonation.timeline
	var text := "%s  T+%.1fs  충격파 %.2f km (과압 %.1f kPa)  구름 정상 %.1f km" % [
		str(detonation.preset.label), detonation.elapsed, tl.shock_radius / 1000.0,
		tl.shock_overpressure * 101.3, (tl.cap_height + tl.cap_half_height) / 1000.0]
	if camera:
		var dist: float = camera.global_position.distance_to(detonation.burst_point)
		var arrival: float = detonation.shock_arrival_at(camera.global_position)
		var state := "통과" if detonation.elapsed >= arrival else "도달까지 %.1f초" % (arrival - detonation.elapsed)
		text += "\n    관측점 %.1f km  충격파 %s" % [dist / 1000.0, state]
	return text

func _resolve_references() -> void:
	if not player_node:
		player_node = get_node_or_null("../Player")
	if not terrain_manager:
		terrain_manager = get_node_or_null("../TerrainManager")
	if not weather_manager:
		weather_manager = get_node_or_null("../WeatherManager")
	if not cloud_manager:
		cloud_manager = get_node_or_null("../WeatherManager/CloudClusterManager")
	if not sun_light:
		sun_light = get_node_or_null("../DirectionalLight3D")
	if not world_environment:
		world_environment = get_node_or_null("../WorldEnvironment")
	if not day_night_service:
		day_night_service = get_node_or_null("../DayNightCycleService")
	if not wind_field:
		wind_field = get_node_or_null("../WeatherManager/WindField")
