extends RefCounted
## 디버그 열람용 커스텀 씬 목록. 새 씬은 자산 폴더에서 자동으로 발견한다.

static func collect() -> Array[Dictionary]:
	var labels: Dictionary = {}
	var path := "res://assets/generated/taehwa_bridges.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for bridge in parsed.get("bridges", []):
				labels[str(bridge.get("preview_scene", ""))] = str(bridge.name)
	labels["res://assets/generated/bridges/bridge_06.scn"] = "범용 하천 교량"
	labels["res://assets/generated/bridges/bridge_07.scn"] = "태화강 징검다리 · 배치 미확정"
	labels["res://assets/generated/pedestrian_bridges/gulhwa_daun_crossing.scn"] = "굴화리–다운동 도보 징검다리"
	labels["res://assets/generated/pedestrian_bridges/seonbawi_bridge.scn"] = "선바위교"
	labels["res://assets/generated/pedestrian_bridges/generic_pedestrian_overpass.scn"] = "범용 보행 육교"
	labels["res://assets/generated/airport/ulsan_airport.scn"] = "울산공항"
	var airport_path := "res://assets/generated/japan_airports/placement.json"
	if FileAccess.file_exists(airport_path):
		var airport_catalog = JSON.parse_string(FileAccess.get_file_as_string(airport_path))
		if airport_catalog is Dictionary:
			for airport in airport_catalog.get("airports", []):
				labels[str(airport.scene_path)] = str(airport.name_ko)
	labels["res://assets/generated/heritage/ulsan_waeseong.scn"] = "울산왜성"
	labels["res://assets/generated/heritage/eonyang_eupseong.scn"] = "언양읍성 · 영화루"
	var paths: Array[String] = []
	_scan("res://assets", paths)
	paths.sort()
	var result: Array[Dictionary] = []
	for scene_path in paths:
		result.append({"name": labels.get(scene_path, scene_path.get_file().get_basename()), "path": scene_path})
	return result

static func _scan(folder: String, result: Array[String]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file in dir.get_files():
		var original := file.trim_suffix(".remap")
		if original.get_extension() in ["scn", "tscn"]:
			var path := folder.path_join(original)
			if not result.has(path):
				result.append(path)
	for child in dir.get_directories():
		_scan(folder.path_join(child), result)

