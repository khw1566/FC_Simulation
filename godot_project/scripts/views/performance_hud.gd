extends CanvasLayer
## 저비용 FPS 표시. 프레임 시간은 실제 프레임 간 벽시계 시간으로 측정한다.
var _label: Label
var _elapsed := 0.0
var _frames := 0
var _peak_ms := 0.0
var _previous_usec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
	set_hud_visible(get_node("/root/UserSettingsService").fps_display_enabled)

func set_hud_visible(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	_elapsed = 0.0
	_frames = 0
	_peak_ms = 0.0
	_previous_usec = Time.get_ticks_usec()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		var enabled := not visible
		set_hud_visible(enabled)
		var settings := get_node("/root/UserSettingsService")
		settings.fps_display_enabled = enabled
		settings.save_settings()
		var view := get_parent().get_node_or_null("CanvasLayer/PauseSettingsHUD")
		if view:
			view.fps_check.set_pressed_no_signal(enabled)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var seconds := float(now - _previous_usec) / 1000000.0
	_previous_usec = now
	_elapsed += seconds
	_frames += 1
	_peak_ms = maxf(_peak_ms, seconds * 1000.0)
	if _elapsed < 0.5:
		return
	_label.text = "%.0f FPS | 평균 %.1f ms | 최대 %.1f ms [F3]\n업로드 최대 %.1f ms | 드로우 %d" % [
		float(_frames)/_elapsed,_elapsed*1000.0/_frames,_peak_ms,
		preload("res://scripts/terrain/stream_frame_budget.gd").recent_peak_ms(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	_elapsed = 0.0
	_frames = 0
	_peak_ms = 0.0

