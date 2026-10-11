extends "res://scripts/terrain/riverside_trial_placer.gd"
class_name BridgeTrialPlacer

## 태화강 조사 교량 초안 시범 배치기. taehwa_bridge_trial/placements.json의 양 끝 위경도로
## 중심·방향을 정하고, 양 끝 지형 높이 평균(bank_ends) 또는 지도 해수면(sea_level)에 상판을 맞춘다.
## 모델 로딩과 좌표 변환은 RiversideTrialPlacer를 재사용한다.

const BRIDGE_CATALOG := "res://assets/generated/taehwa_bridge_trial/placements.json"

func _initialize() -> void:
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or not FileAccess.file_exists(BRIDGE_CATALOG):
		load_complete = true
		return
	while is_instance_valid(terrain_manager) and not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(BRIDGE_CATALOG))
	if catalog is Dictionary:
		place_all(catalog.get("placements", []), maps.selected_map)
	print("BridgeTrialPlacer: ", placed_count, " placed")
	load_complete = true

func place_all(entries: Array, map) -> void:
	for entry in entries:
		if not entry is Dictionary or not _inside(entry.lonlat_start, map) or not _inside(entry.lonlat_end, map):
			continue
		var node := _instantiate(str(entry.get("scene", "")))
		if node == null:
			push_warning("교량 시범 배치 건너뜀: " + str(entry.get("id", "?")))
			continue
		node.name = str(entry.get("id", "BridgeTrial"))
		var a := _world_xz(entry.lonlat_start, map)
		var b := _world_xz(entry.lonlat_end, map)
		var mid := (a + b) * 0.5
		var dir := b - a
		node.position = Vector3(mid.x, _deck_y(entry, a, b, map) + float(entry.get("y_offset_m", 0.0)), mid.y)
		# 모델 길이축은 로컬 +Z이며 Start(-Z)에서 End(+Z)로 향한다
		node.rotation.y = atan2(dir.x, dir.y)
		node.scale = Vector3.ONE * float(entry.get("scale", 1.0))
		add_child(node)
		placed_count += 1

func _deck_y(entry: Dictionary, a: Vector2, b: Vector2, map) -> float:
	var sea: float = map.sea_level if map.sea_level > -900.0 else 0.0
	if str(entry.get("ground", "bank_ends")) == "sea_level" or not is_instance_valid(terrain_manager):
		return sea
	var banks: float = (terrain_manager.get_terrain_elevation(a.x, a.y) + terrain_manager.get_terrain_elevation(b.x, b.y)) * 0.5
	return maxf(banks, sea)
