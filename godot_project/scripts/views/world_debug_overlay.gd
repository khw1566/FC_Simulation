extends CanvasLayer
## F10 중앙 대상 조사 HUD. 숨긴 동안 광선 검사를 수행하지 않는다.
const Probe = preload("res://scripts/services/center_object_probe.gd")
const Geo = preload("res://scripts/core/geo_coordinate_converter.gd")
var _probe := Probe.new()
var _panel: PanelContainer
var _label: Label
var _enabled := false
var _elapsed := 0.0

func _ready() -> void:
	layer = 90
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 250)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.91)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_panel.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_enabled = not _enabled
		_panel.visible = _enabled
		_elapsed = 1.0
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	var player := get_parent().get_node_or_null("Player") as CollisionObject3D
	if camera == null or player == null:
		_label.text = "F10 디버그 · 카메라 또는 플레이어 없음"
		return
	var result: Dictionary = _probe.inspect(camera, player.get_rid())
	var geo: Dictionary = Geo.world_to_geo(player.global_position)
	var lines := PackedStringArray(["F10 디버그 | 화면 중앙 광선 | %.0f FPS" % Engine.get_frames_per_second(),
		"플레이어 XYZ: %.2f, %.2f, %.2f m" % [player.global_position.x, player.global_position.y, player.global_position.z],
		"위도 %.6f / 경도 %.6f" % [geo.lat, geo.lon]])
	var collision: Dictionary = result.collision
	if collision.is_empty():
		lines.append("물리 충돌: 없음 (물·원거리 지형은 충돌체가 없을 수 있음)")
	else:
		lines.append("물리 충돌: " + str(collision.collider.get_path()))
	lines.append("중앙 메시 후보: %d개 / 가까운 8개 검사" % result.candidate_count)
	var terrain := get_parent().get_node_or_null("TerrainManager")
	for hit in result.render_hits.slice(0, 3):
		lines.append("%s · %.1fm" % [hit.path, hit.distance])
		lines.append("  재질: " + hit.material)
		var p: Vector3 = hit.position
		lines.append("  교점 XYZ: %.1f, %.1f, %.1f" % [p.x, p.y, p.z])
		if terrain != null:
			lines.append("  수계 %.3f / 지형고 %.2fm" % [terrain.call("get_water_mask", p.x, p.z), terrain.call("get_terrain_elevation", p.x, p.z)])
	lines.append("메시 후보는 투명도·셰이더 절삭/변위를 반영하지 않습니다.")
	_label.text = "\n".join(lines)
