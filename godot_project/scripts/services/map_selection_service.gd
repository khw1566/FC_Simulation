extends Node

const MapConfigModelClass = preload("res://scripts/models/map_config_model.gd")

var maps: Array = []
var selected_map = null
var current_language: String = "ko"

func _ready() -> void:
	load_all_maps()

func load_all_maps() -> void:
	maps.clear()
	selected_map = null
	var registry_path := "res://assets/maps/maps_registry.json"
	if not FileAccess.file_exists(registry_path):
		push_error("[MapSelectionService] Registry file not found: " + registry_path)
		_load_default_fallback()
		return

	var file := FileAccess.open(registry_path, FileAccess.READ)
	var content := file.get_as_text()
	var reg_data = JSON.parse_string(content)
	if typeof(reg_data) != TYPE_DICTIONARY:
		push_error("[MapSelectionService] Invalid registry format.")
		_load_default_fallback()
		return

	var default_id: String = reg_data.get("default_map_id", "kanmon_straits")
	var map_items = reg_data.get("maps", [])

	for item in map_items:
		var meta_path: String = item.get("meta_file", "")
		if FileAccess.file_exists(meta_path):
			var m_file := FileAccess.open(meta_path, FileAccess.READ)
			var m_dict = JSON.parse_string(m_file.get_as_text())
			if typeof(m_dict) == TYPE_DICTIONARY:
				var model = MapConfigModelClass.create_from_dict(m_dict)
				maps.append(model)
				if model.id == default_id:
					selected_map = model

	if selected_map == null and maps.size() > 0:
		selected_map = maps[0]

	print("[MapSelectionService] Successfully loaded %d maps." % [maps.size()])

func _load_default_fallback() -> void:
	var fallback_dict := {
		"id": "kanmon_straits",
		"category": "japan",
		"name_ko": "칸몬 해협",
		"name_en": "Kanmon Straits",
		"description_ko": "기본 칸몬 해협 맵",
		"description_en": "Default Kanmon Straits Map",
		"world_size_meters": 28000.0,
		"min_elevation": -50.0,
		"max_elevation": 750.0,
		"sea_level": 0.0,
		"assets": {
			"heightmap": "res://assets/maps/kanmon_straits/kanmon_heightmap_16bit.png",
			"watermask": "res://assets/maps/kanmon_straits/kanmon_watermask_8bit.png",
			"splatmap": "res://assets/maps/kanmon_straits/kanmon_splatmap_rgba.png",
			"tactical_map": "res://assets/maps/kanmon_straits/kanmon_vector_tactical_map.png",
			"districts": "res://assets/maps/kanmon_straits/real_districts.json",
			"buildings_roads": "res://assets/maps/kanmon_straits/buildings_and_roads.json",
			"landmarks": "res://assets/maps/kanmon_straits/landmarks.json"
		}
	}
	selected_map = MapConfigModelClass.create_from_dict(fallback_dict)
	maps.append(selected_map)

func select_map_by_id(map_id: String) -> bool:
	for m in maps:
		if m.id == map_id:
			selected_map = m
			return true
	return false

func toggle_language() -> String:
	current_language = "en" if current_language == "ko" else "ko"
	return current_language
