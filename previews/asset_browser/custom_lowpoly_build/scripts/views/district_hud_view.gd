extends Control
class_name DistrictHUDView

@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var district_name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/DistrictNameLabel
@onready var region_info_label: Label = $PanelContainer/MarginContainer/VBoxContainer/RegionInfoLabel
@onready var landmarks_header_label: Label = $PanelContainer/MarginContainer/VBoxContainer/LandmarksHeaderLabel
@onready var landmarks_label: Label = $PanelContainer/MarginContainer/VBoxContainer/LandmarksLabel
@onready var attribution_label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/AttributionLabel
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var current_lang: String = "ko"
var current_district = null
var translations: Dictionary = {}

func _ready() -> void:
	load_translations()
	if attribution_label:
		attribution_label.meta_clicked.connect(_open_attribution_link)
	update_hud_display()

func _open_attribution_link(meta) -> void:
	OS.shell_open(str(meta))

func load_translations() -> void:
	var path := "res://assets/translations.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var res = JSON.parse_string(file.get_as_text())
		if typeof(res) == TYPE_DICTIONARY:
			translations = res

func toggle_language() -> void:
	current_lang = "en" if current_lang == "ko" else "ko"
	update_hud_display()

func display_district(district) -> void:
	current_district = district
	update_hud_display()
	if anim_player and anim_player.has_animation("popup"):
		anim_player.play("popup")

func update_hud_display() -> void:
	var t: Dictionary = translations.get(current_lang, {})
	if title_label:
		title_label.text = t.get("ui_district_title", "CURRENT DISTRICT")

	if not current_district:
		if district_name_label:
			district_name_label.text = "---"
		if region_info_label:
			region_info_label.text = ""
		if landmarks_label:
			landmarks_label.text = ""
		if attribution_label:
			attribution_label.visible = false
		return

	if district_name_label:
		district_name_label.text = current_district.get_localized_name(current_lang)
	if region_info_label:
		if not current_district.admin_hierarchy.is_empty():
			region_info_label.text = current_district.get_admin_hierarchy_label()
		else:
			region_info_label.text = current_district.prefecture + " | " + current_district.city
	if landmarks_header_label:
		landmarks_header_label.text = t.get("ui_landmarks_header", "LANDMARKS")
	if landmarks_label:
		var lm_text := ""
		for lm in current_district.landmarks:
			lm_text += "- " + str(lm) + "\n"
		landmarks_label.text = lm_text.strip_edges()
	if attribution_label:
		attribution_label.visible = current_district.admin_level >= 0
