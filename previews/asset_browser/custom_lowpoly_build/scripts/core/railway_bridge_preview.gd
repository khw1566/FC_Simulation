extends Control
## 범용 철도 교량과 안양교 연결 세트의 독립 프리뷰.

const Preview = preload("res://scripts/views/custom_asset_preview.gd")
var preview
var label: Label
var picker: OptionButton
var models: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/railway_bridges/catalog.json"))
	models = catalog.models
	var background := ColorRect.new()
	background.color = Color(0.035, 0.035, 0.035)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	picker = OptionButton.new()
	for model in models:
		picker.add_item(str(model.name_ko))
	picker.item_selected.connect(select_model)
	column.add_child(picker)
	label = Label.new()
	column.add_child(label)
	preview = Preview.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var help := Label.new()
	help.text = "드래그: 회전 / 휠: 확대 / Shift+드래그: 이동 / R: 시점 초기화 / Esc: 종료\n연결 세트는 게임용 직선 조립 모델이며 지도상의 실제 배치와 분리되어 있습니다."
	column.add_child(help)
	call_deferred("select_model", models.size() - 1)

func select_model(index: int) -> void:
	picker.select(index)
	var data: Dictionary = models[index]
	var error: String = preview.show_scene(str(data.scene_path))
	preview.yaw = 1.12
	preview.pitch = 0.26
	preview.distance *= 0.65
	preview._update_camera()
	label.text = "%s | 길이 %.1f m | 궤간 1.435 m | 궤도 기준 높이 Y=0.12 m" % [data.name_ko, data.length_m] if error.is_empty() else error

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_R:
			select_model(picker.selected)
