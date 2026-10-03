extends Node
class_name MapSelectionController

@export var view_node: Control

var _translations: Dictionary = {}

func _ready() -> void:
	_load_translations()
	if not view_node:
		view_node = get_parent() as Control

	if view_node:
		if view_node.has_signal("map_selected"):
			view_node.map_selected.connect(_on_map_selected)
		if view_node.has_signal("enter_world_requested"):
			view_node.enter_world_requested.connect(_on_enter_world_requested)
		if view_node.has_signal("language_toggled"):
			view_node.language_toggled.connect(_on_language_toggled)

	# view_node의 자식 노드들이 _ready()를 마친 후 안전하게 UI 갱신 호출
	call_deferred("_refresh_ui")

func _load_translations() -> void:
	var path := "res://assets/translations.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		var res = JSON.parse_string(file.get_as_text())
		if typeof(res) == TYPE_DICTIONARY:
			_translations = res

func _get_service() -> Node:
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		return root.get_node("MapSelectionService")
	return null

func _refresh_ui() -> void:
	var svc = _get_service()
	if not svc or not view_node:
		return

	var lang: String = svc.current_language
	var lang_dict: Dictionary = _translations.get(lang, {})

	if view_node.has_method("update_localization"):
		view_node.update_localization(lang_dict)

	var selected_id: String = svc.selected_map.id if svc.selected_map else ""
	if view_node.has_method("populate_map_list"):
		view_node.populate_map_list(svc.maps, selected_id, lang)

	if view_node.has_method("display_map_detail"):
		view_node.display_map_detail(svc.selected_map, lang)

func _on_map_selected(map_model) -> void:
	var svc = _get_service()
	if svc:
		svc.selected_map = map_model
		var lang: String = svc.current_language
		if view_node and view_node.has_method("display_map_detail"):
			view_node.display_map_detail(map_model, lang)

func _on_language_toggled() -> void:
	var svc = _get_service()
	if svc:
		svc.toggle_language()
		_refresh_ui()

func _on_enter_world_requested() -> void:
	var svc = _get_service()
	if svc and svc.selected_map:
		print("[MapSelectionController] Entering map via LoadingManagerService: ", svc.selected_map.id)
	var root = get_tree().root
	if root.has_node("LoadingManagerService"):
		var loader = root.get_node("LoadingManagerService")
		loader.transition_to_map()
	else:
		get_tree().change_scene_to_file("res://scenes/main_world.tscn")
