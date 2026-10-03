extends Node
class_name DistrictService

const DistrictModelClass = preload("res://scripts/models/district_model.gd")

signal district_changed(district)

var districts: Array = []
var current_district = null

func _ready() -> void:
	load_districts()

func load_districts() -> void:
	districts.clear()

	var target_path: String = ""
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			target_path = svc.selected_map.districts_path

	if target_path.is_empty() or not FileAccess.file_exists(target_path):
		var real_path := "res://assets/maps/kanmon_straits/real_districts.json"
		var legacy_path := "res://assets/generated/real_districts.json"
		var fallback_path := "res://../config/administrative_districts.json"

		if FileAccess.file_exists(real_path):
			target_path = real_path
		elif FileAccess.file_exists(legacy_path):
			target_path = legacy_path
		else:
			target_path = fallback_path

	if not FileAccess.file_exists(target_path):
		push_warning("[DistrictService] No districts file found at: " + target_path)
		return

	var file := FileAccess.open(target_path, FileAccess.READ)
	var text := file.get_as_text()
	var json_res = JSON.parse_string(text)
	if typeof(json_res) != TYPE_ARRAY:
		push_error("[DistrictService] Districts JSON parsing error.")
		return

	for item in json_res:
		var model = DistrictModelClass.new()
		model.id = item.get("id", "")
		model.name_ko = item.get("name_ko", "")
		model.name_en = item.get("name_en", "")
		model.prefecture = item.get("prefecture", "")
		model.city = item.get("city", "")
		model.admin_name = item.get("admin_name", "")
		model.admin_level = int(item.get("admin_level", -1))
		model.landmarks = item.get("landmarks", [])

		if item.has("polygon"):
			model.set_polygon(item.get("polygon", []))
		elif item.has("world_bounds"):
			var b = item.get("world_bounds", {})
			var min_x = float(b.get("min_x", 0.0))
			var max_x = float(b.get("max_x", 0.0))
			var min_z = float(b.get("min_z", 0.0))
			var max_z = float(b.get("max_z", 0.0))
			model.set_polygon([[min_x, min_z], [max_x, min_z], [max_x, max_z], [min_x, max_z]])

		districts.append(model)

	print("[DistrictService] Loaded ", districts.size(), " districts from ", target_path)

func update_player_position(pos: Vector3) -> void:
	var matching_admin: Array = []
	var fallback_district = null
	for d in districts:
		if d.is_point_inside(pos):
			if d.admin_level >= 0:
				matching_admin.append(d)
			elif fallback_district == null:
				fallback_district = d

	var selected = fallback_district
	if not matching_admin.is_empty():
		matching_admin.sort_custom(Callable(self, "_sort_admin_levels"))
		selected = matching_admin[-1]
		var hierarchy: Array = []
		for match in matching_admin:
			if hierarchy.is_empty() or hierarchy[-1] != match.admin_name:
				hierarchy.append(match.admin_name)
		selected.admin_hierarchy = hierarchy

	if selected != null and current_district != selected:
		current_district = selected
		district_changed.emit(current_district)
	elif selected == null and current_district != null:
		current_district = null
		district_changed.emit(current_district)

func _sort_admin_levels(a, b) -> bool:
	return a.admin_level < b.admin_level
