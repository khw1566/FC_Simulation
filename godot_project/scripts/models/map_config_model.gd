extends RefCounted
class_name MapConfigModel

var id: String = ""
var category: String = "testing"
var name_ko: String = ""
var name_en: String = ""
var description_ko: String = ""
var description_en: String = ""
var preview_image: String = ""
var world_size_meters: float = 28000.0
var min_elevation: float = -50.0
var max_elevation: float = 750.0
var sea_level: float = 0.0
var spawn_position: Vector3 = Vector3(0.0, 350.0, 0.0)

var bbox_south: float = 33.8000
var bbox_north: float = 34.0500
var bbox_west: float = 130.8000
var bbox_east: float = 131.1000

var heightmap_path: String = ""
var watermask_path: String = ""
var splatmap_path: String = ""
var tactical_map_path: String = ""
var districts_path: String = ""
var buildings_roads_path: String = ""
var landmarks_path: String = ""
var airport_placement_path: String = ""
var vector_source_meta: String = ""
var sea_mask_path: String = ""
var river_mask_path: String = ""
var lake_mask_path: String = ""
var coastal_heightmap_corrected: bool = false

static func create_from_dict(dict: Dictionary):
	var model = load("res://scripts/models/map_config_model.gd").new()
	model.id = dict.get("id", "")
	model.category = dict.get("category", "testing")
	model.vector_source_meta = dict.get("vector_source_meta", "")
	model.coastal_heightmap_corrected = bool(dict.get("coastal_heightmap_corrected", false))
	model.name_ko = dict.get("name_ko", "")
	model.name_en = dict.get("name_en", "")
	model.description_ko = dict.get("description_ko", "")
	model.description_en = dict.get("description_en", "")
	model.preview_image = dict.get("preview_image", "")
	model.world_size_meters = float(dict.get("world_size_meters", 28000.0))
	model.min_elevation = float(dict.get("min_elevation", -50.0))
	model.max_elevation = float(dict.get("max_elevation", 750.0))
	model.sea_level = float(dict.get("sea_level", 0.0))

	var spawn = dict.get("spawn_position", [0.0, 350.0, 0.0])
	if typeof(spawn) == TYPE_ARRAY and spawn.size() >= 3:
		model.spawn_position = Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2]))

	var bbox = dict.get("bbox", {})
	if typeof(bbox) == TYPE_DICTIONARY:
		model.bbox_south = float(bbox.get("south", 33.8000))
		model.bbox_north = float(bbox.get("north", 34.0500))
		model.bbox_west = float(bbox.get("west", 130.8000))
		model.bbox_east = float(bbox.get("east", 131.1000))

	var assets = dict.get("assets", {})
	if typeof(assets) == TYPE_DICTIONARY:
		model.heightmap_path = assets.get("heightmap", "")
		model.watermask_path = assets.get("watermask", "")
		model.sea_mask_path = assets.get("sea_mask", "")
		model.river_mask_path = assets.get("river_mask", "")
		model.lake_mask_path = assets.get("lake_mask", "")
		model.splatmap_path = assets.get("splatmap", "")
		model.tactical_map_path = assets.get("tactical_map", "")
		model.districts_path = assets.get("districts", "")
		model.buildings_roads_path = assets.get("buildings_roads", "")
		model.landmarks_path = assets.get("landmarks", "")
		model.airport_placement_path = assets.get("airport_placement", "")

	return model

func get_localized_name(lang: String) -> String:
	return name_ko if lang == "ko" else name_en

func get_localized_desc(lang: String) -> String:
	return description_ko if lang == "ko" else description_en
