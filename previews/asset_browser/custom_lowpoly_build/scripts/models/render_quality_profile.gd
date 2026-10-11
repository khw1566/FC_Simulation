extends RefCounted
class_name RenderQualityProfile

## 지도 로딩과 표시가 공유하는 품질 정책. 지리적 범위는 변경하지 않는다.
const IDS := ["light", "standard", "high"]
const PROFILES := {
	"light": {"initial_radius": 2000.0, "view_distance": 5000.0, "prefetch": 1500.0, "minor_distance": 2000.0, "base_resolution": 64, "height_width": 2816, "rail_edge": 40.0, "rail_detail": 1500.0},
	"standard": {"initial_radius": 3500.0, "view_distance": 7000.0, "prefetch": 2000.0, "minor_distance": 3000.0, "base_resolution": 128, "height_width": 5632, "rail_edge": 20.0, "rail_detail": 2000.0},
	"high": {"initial_radius": 5000.0, "view_distance": 9000.0, "prefetch": 2500.0, "minor_distance": 4500.0, "base_resolution": 128, "height_width": 5632, "rail_edge": 10.0, "rail_detail": 3500.0}
}

static func normalize(value: String) -> String:
	return value if value in IDS else "light"

static func get_profile(value: String) -> Dictionary:
	var id := normalize(value)
	var result: Dictionary = PROFILES[id].duplicate()
	result["id"] = id
	return result

static func current() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null("UserSettingsService") if tree else null
	return get_profile(settings.session_quality if settings else "light")

static func heightmap_path(config) -> String:
	var path: String = config.heightmap_path
	var graded := "res://assets/generated/railway/graded_heightmap_16bit.png"
	if config.id == "ulsan_metro_80km" and FileAccess.file_exists(graded):
		path = graded
	if current().id != "light":
		return path
	var manifest_path := "res://assets/generated/terrain_quality/%s/light/manifest.json" % config.id
	if not FileAccess.file_exists(manifest_path):
		return path
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		return path
	for record in manifest.get("assets", {}).values():
		if record.get("type", "") != "terrain_quality_heightmap":
			continue
		var meta: Dictionary = record.get("metadata", {})
		if meta.get("source_path", "") != path or int(meta.get("source_modified", -1)) != FileAccess.get_modified_time(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file and file.get_length() == int(meta.get("source_size", -1)) and FileAccess.file_exists(record.file_path):
			return str(record.file_path)
	return path
