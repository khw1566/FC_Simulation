extends CanvasLayer
class_name NuclearStrikeHudView

## 핵폭발 시뮬레이션 상태 표시(흑백 테마): 선택 위력, 조작 키, 낙하·폭발 경과와 충격파 도달 정보.

var _panel: PanelContainer
var _label: Label

func _ready() -> void:
	layer = 2
	_panel = PanelContainer.new()
	_panel.name = "NuclearStrikePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 왼쪽 아래, 하단 중앙 속도 HUD(하단 80px)보다 위에 두고 내용이 늘면 위로 자란다.
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16.0
	_panel.offset_right = 16.0
	_panel.offset_top = -96.0
	_panel.offset_bottom = -96.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.border_color = Color(0.6, 0.6, 0.6, 0.8)
	style.set_border_width_all(1)
	style.set_content_margin_all(8.0)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_label)
	add_child(_panel)

func show_status(text: String) -> void:
	if _label:
		_label.text = text
