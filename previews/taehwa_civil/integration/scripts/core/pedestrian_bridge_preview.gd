extends Control
## 독립 교량 모델의 선택 및 프리뷰 표시.

const Preview = preload("res://scripts/views/custom_asset_preview.gd")
const MODELS = [
	["gulhwa_daun_crossing", "굴화리–다운동 징검다리", "약 100 × 1 m / 보도 기준 근사 모델"],
	["seonbawi_bridge", "선바위교", "160 × 24.9 m / 상세 부재와 교각은 근사"],
	["generic_pedestrian_overpass", "범용 육교", "중앙 경간 28 × 3 m / 양측 계단 포함"],
]
var preview
var label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	var row := HBoxContainer.new()
	column.add_child(row)
	for i in range(MODELS.size()):
		var button := Button.new()
		button.text = MODELS[i][1]
		button.pressed.connect(select_model.bind(i))
		row.add_child(button)
	label = Label.new()
	column.add_child(label)
	preview = Preview.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var help := Label.new()
	help.text = "드래그: 회전  /  휠: 확대  /  Shift+드래그: 이동  /  1·2·3: 모델 선택  /  Esc: 종료"
	column.add_child(help)
	call_deferred("select_model", 0)

func select_model(index: int) -> void:
	var spec: Array = MODELS[index]
	var error: String = preview.show_scene("res://assets/generated/pedestrian_bridges/%s.scn" % spec[0])
	preview.yaw = 1.05
	preview.pitch = 0.45
	preview.distance *= 0.65
	preview._update_camera()
	label.text = "%s | %s" % [spec[1], spec[2]] if error.is_empty() else error

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode in [KEY_1, KEY_2, KEY_3]:
			select_model(event.keycode - KEY_1)
