extends Node3D
class_name DamLandmarkManager

const CATALOG_PATH := "res://assets/generated/ulsan_dams/catalog.json"
const TerrainFit = preload("res://scripts/terrain/dam_terrain_fit.gd")
var placements: Array[Dictionary] = []

## 지도 좌표계에 축선 두 끝을 정확하게 대응시키며 댐마루만 DEM에 맞춘다.
func setup(config, terrain: Node3D, catalog_path: String = CATALOG_PATH, scene_root: String = "") -> void:
	for placement in placements:
		placement.model.free()
	placements.clear()
	if config == null or not is_instance_valid(terrain) or not terrain.has_method("get_terrain_elevation"):
		return
	if not str(config.id).begins_with("ulsan_") and not str(config.id).begins_with("southeast_"):
		return
	if not FileAccess.file_exists(catalog_path):
		return
	var document = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not document is Dictionary:
		return
	for spec in document.get("models", []):
		var axis: Array = spec.get("axis_lonlat", [])
		if axis.size() != 2 or not _inside(axis[0], config) or not _inside(axis[1], config):
			continue
		var a := _world(axis[0], config)
		var b := _world(axis[1], config)
		var delta := b - a
		if delta.length() < 1.0:
			continue
		var path := str(spec.scene_path) if scene_root.is_empty() else scene_root.path_join(str(spec.id) + ".tscn")
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("댐 씬을 읽지 못했습니다: " + path)
			continue
		var model := packed.instantiate() as Node3D
		model.name = str(spec.id)
		add_child(model)
		var center := (a+b)*0.5
		var north_scale: float = config.world_size_meters / ((config.bbox_north-config.bbox_south)*111320.0)
		var east_scale: float = config.world_size_meters / ((config.bbox_east-config.bbox_west)*111320.0*cos(deg_to_rad(float(spec.anchor.lat))))
		var yaw: float = float(spec.axis_yaw_rad)
		# X는 실제 축선 길이, Z는 지도 경위도 축별 비율을 보존한다.
		var cross_axis := Vector3(sin(yaw)*east_scale, 0, cos(yaw)*north_scale)
		model.basis = Basis(delta/float(spec.official_length_m), Vector3.UP, cross_axis)
		var heights: Array[float] = []
		for step in range(2,19):
			var p := a.lerp(b, float(step)/20.0)
			heights.append(float(terrain.call("get_terrain_elevation",p.x,p.z)))
		heights.sort()
		center.y = heights[floori((heights.size()-1)*0.9)] + 0.35
		model.position = center
		TerrainFit.apply(model, terrain)
		placements.append({"model":model,"spec":spec,"crest_y_m":center.y,"height_status":"dem_estimate"})
	print("[DamLandmarkManager] 울산 댐 배치: ", placements.size())

func _inside(point: Array, config) -> bool:
	return float(point[0]) >= config.bbox_west and float(point[0]) <= config.bbox_east and float(point[1]) >= config.bbox_south and float(point[1]) <= config.bbox_north

func _world(point: Array, config) -> Vector3:
	return Vector3(((float(point[0])-config.bbox_west)/(config.bbox_east-config.bbox_west)-0.5)*config.world_size_meters, 0, ((config.bbox_north-float(point[1]))/(config.bbox_north-config.bbox_south)-0.5)*config.world_size_meters)
