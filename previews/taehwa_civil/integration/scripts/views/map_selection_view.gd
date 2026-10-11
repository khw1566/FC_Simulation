extends Control
class_name MapSelectionView

signal map_selected(map_model)
signal enter_world_requested()
signal language_toggled()

@onready var title_label: Label = $RootMargin/MainLayout/Header/HeaderLeft/TitleLabel
@onready var subtitle_label: Label = $RootMargin/MainLayout/Header/HeaderLeft/SubtitleLabel
@onready var lang_button: Button = $RootMargin/MainLayout/Header/HeaderRight/LangButton

@onready var map_list_container: VBoxContainer = $RootMargin/MainLayout/BodyLayout/LeftPanel/ListMargin/ListScroll/MapListVBox

@onready var preview_rect: TextureRect = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/PreviewFrame/PreviewTexture
@onready var detail_title: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/DetailTitle
@onready var detail_desc: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/DetailDesc

@onready var stat_world_size_val: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/WorldSizeValue
@onready var stat_elevation_val: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/ElevationValue
@onready var stat_sea_level_val: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/SeaLevelValue
@onready var stat_bbox_val: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/BBoxValue

@onready var stat_world_size_lbl: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/WorldSizeLabel
@onready var stat_elevation_lbl: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/ElevationLabel
@onready var stat_sea_level_lbl: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/SeaLevelLabel
@onready var stat_bbox_lbl: Label = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/StatsGrid/BBoxLabel

@onready var enter_button: Button = $RootMargin/MainLayout/BodyLayout/RightPanel/DetailMargin/DetailVBox/BottomActions/EnterButton

var _map_buttons: Dictionary = {}
const Quality = preload("res://scripts/models/render_quality_profile.gd")
const CATEGORIES := ["japan", "korea", "testing"]
const CATEGORY_NAMES := {"japan": ["일본", "Japan"], "korea": ["한국", "Korea"], "testing": ["테스팅", "Testing"]}

func _ready() -> void:
	_add_quality_selector()
	if lang_button:
		lang_button.pressed.connect(func(): language_toggled.emit())
	if enter_button:
		enter_button.pressed.connect(func(): enter_world_requested.emit())

func _add_quality_selector() -> void:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.text = "시작 품질"
	row.add_child(label)
	var selector := OptionButton.new()
	selector.name = "QualitySelector"
	for title in ["경량 (기본) · 빠른 시작", "표준 · 균형", "고품질 · 상세 표시"]:
		selector.add_item(title)
	selector.custom_minimum_size = Vector2(230, 36)
	row.add_child(selector)
	var settings := get_node_or_null("/root/UserSettingsService")
	selector.select(Quality.IDS.find(settings.render_quality) if settings else 0)
	selector.item_selected.connect(func(index: int):
		if settings:
			settings.set_render_quality(Quality.IDS[index]))
	selector.tooltip_text = "지도·지형·건물·철도 상세 범위를 함께 변경합니다. 적용은 다음 지도 시작 시 이루어집니다."
	var actions := enter_button.get_parent()
	actions.add_child(row)
	actions.move_child(row, 0)

func populate_map_list(maps: Array, selected_id: String, lang: String) -> void:
	for child in map_list_container.get_children():
		map_list_container.remove_child(child)
		child.queue_free()
	_map_buttons.clear()

	for category in CATEGORIES:
		var heading := Label.new()
		heading.text = CATEGORY_NAMES[category][0 if lang == "ko" else 1]
		heading.add_theme_font_size_override("font_size", 18)
		heading.add_theme_color_override("font_color", Color.WHITE)
		map_list_container.add_child(heading)
		for m in maps:
			if m.category == category:
				_add_map_button(m, selected_id, lang)

func _add_map_button(m, selected_id: String, lang: String) -> void:
	var btn := Button.new()
	btn.text = m.get_localized_name(lang)
	btn.custom_minimum_size = Vector2(0, 52)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 16)
	_apply_button_monochrome_style(btn, m.id == selected_id)

	btn.pressed.connect(func():
		_highlight_selected_button(m.id)
		map_selected.emit(m)
	)

	map_list_container.add_child(btn)
	_map_buttons[m.id] = btn

func _highlight_selected_button(selected_id: String) -> void:
	for id in _map_buttons.keys():
		var btn: Button = _map_buttons[id]
		_apply_button_monochrome_style(btn, id == selected_id)

func _apply_button_monochrome_style(btn: Button, is_selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0

	if is_selected:
		style.bg_color = Color(0.9, 0.9, 0.9, 1.0)
		style.border_width_left = 4
		style.border_color = Color(0.1, 0.1, 0.1, 1.0)
		btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0, 1.0))
	else:
		style.bg_color = Color(0.12, 0.12, 0.12, 1.0)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.25, 0.25, 0.25, 1.0)
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

func display_map_detail(map_model, lang: String) -> void:
	if not map_model:
		return

	if detail_title:
		detail_title.text = map_model.get_localized_name(lang)
	if detail_desc:
		detail_desc.text = map_model.get_localized_desc(lang)

	if stat_world_size_val:
		stat_world_size_val.text = "%.1f km x %.1f km" % [map_model.world_size_meters / 1000.0, map_model.world_size_meters / 1000.0]
	if stat_elevation_val:
		stat_elevation_val.text = "%.0f m ~ %.0f m" % [map_model.min_elevation, map_model.max_elevation]
	if stat_sea_level_val:
		stat_sea_level_val.text = "%.1f m" % map_model.sea_level
	if stat_bbox_val:
		stat_bbox_val.text = "%.2f~%.2f N / %.2f~%.2f E" % [map_model.bbox_south, map_model.bbox_north, map_model.bbox_west, map_model.bbox_east]

	# 미리보기 이미지 로드
	if preview_rect:
		var preview_path: String = map_model.preview_image
		if preview_path.is_empty() or not FileAccess.file_exists(preview_path):
			preview_path = map_model.tactical_map_path
		if not FileAccess.file_exists(preview_path):
			preview_path = "res://assets/maps/kanmon_straits/kanmon_vector_tactical_map.png"

		if FileAccess.file_exists(preview_path):
			var img := Image.load_from_file(preview_path)
			if img:
				preview_rect.texture = ImageTexture.create_from_image(img)

func update_localization(dict: Dictionary) -> void:
	if title_label:
		title_label.text = dict.get("map_selection_title", "가상 공간 지형 맵 선택 시스템")
	if subtitle_label:
		subtitle_label.text = dict.get("map_selection_subtitle", "탐색할 지형 데이터를 선택하십시오")
	if enter_button:
		enter_button.text = dict.get("btn_enter_world", "선택한 맵으로 공간 진입")
	if lang_button:
		lang_button.text = dict.get("btn_lang_toggle", "언어 전환 (KO / EN)")

	if stat_world_size_lbl:
		stat_world_size_lbl.text = dict.get("stat_world_size", "월드 스케일")
	if stat_elevation_lbl:
		stat_elevation_lbl.text = dict.get("stat_elevation", "표고 범위")
	if stat_sea_level_lbl:
		stat_sea_level_lbl.text = dict.get("stat_sea_level", "기준 해수면")
	if stat_bbox_lbl:
		stat_bbox_lbl.text = dict.get("stat_bbox", "지리적 경계")
