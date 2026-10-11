extends Node3D
class_name BridgeLandmarkManager

const Builder = preload("res://scripts/terrain/bridge_landmark_builder.gd")
const SPEC_PATH := "res://assets/generated/taehwa_bridges.json"
const PlacedAssets = preload("res://scripts/terrain/pedestrian_bridge_placement.gd")
var placed_assets: Node3D
var replaced_osm_ids: Dictionary = {}
# 도로 자료에 OSM ID가 없는 지도도 있으므로 교량 위치와 겹치는 범용 교량을 형상으로 대체한다.
const OVERLAP_MARGIN_M := 8.0
const OVERLAP_RATIO := 0.8
const SAMPLE_STEP_M := 5.0
var _decks: Array[Dictionary] = []

func setup(map_config, terrain: Node3D) -> void:
	placed_assets = PlacedAssets.new()
	placed_assets.name = "PedestrianBridgeAssets"
	add_child(placed_assets)
	placed_assets.setup(map_config, terrain)
	if map_config == null or map_config.bbox_west > 129.27 or map_config.bbox_east < 129.41:
		return
	if map_config.bbox_south > 35.51 or map_config.bbox_north < 35.56:
		return
	if not FileAccess.file_exists(SPEC_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	if not data is Dictionary:
		return
	for spec in data.get("bridges", []):
		var curve := Curve3D.new()
		for p in spec.get("geometry", []):
			var x: float = (float(p.lon) - map_config.bbox_west) / (map_config.bbox_east - map_config.bbox_west) - 0.5
			var z: float = (map_config.bbox_north - float(p.lat)) / (map_config.bbox_north - map_config.bbox_south) - 0.5
			curve.add_point(Vector3(x, 0.0, z) * map_config.world_size_meters)
		if curve.point_count < 2:
			continue
		add_child(Builder.build(spec, curve, terrain))
		for osm_id in spec.osm_ids:
			replaced_osm_ids[str(osm_id)] = true
		_register_deck(curve, float(spec.width_m))

func replaces_road(road: Dictionary) -> bool:
	if replaced_osm_ids.has(str(road.get("osm_id", ""))) or (placed_assets != null and placed_assets.replaces_road(road)):
		return true
	return bool(road.get("bridge", false)) and _overlaps_deck(road.get("points", []))

func _register_deck(curve: Curve3D, width: float) -> void:
	var points := PackedVector2Array()
	for index in curve.point_count:
		var p := curve.get_point_position(index)
		points.append(Vector2(p.x, p.z))
	var reach := width * 0.5 + OVERLAP_MARGIN_M
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	_decks.append({"points": points, "reach": reach, "bounds": bounds.grow(reach)})

## 범용 교량 길이의 대부분이 커스텀 교량 상판 폭 안에 있으면 같은 교량으로 본다.
func _overlaps_deck(raw_points: Array) -> bool:
	if raw_points.size() < 2 or _decks.is_empty():
		return false
	var line := PackedVector2Array()
	for p in raw_points:
		line.append(Vector2(float(p[0]), float(p[p.size() - 1])))
	for deck in _decks:
		var total := 0.0
		var inside := 0.0
		for index in range(1, line.size()):
			var a := line[index - 1]
			var b := line[index]
			var length := a.distance_to(b)
			var count := maxi(1, ceili(length / SAMPLE_STEP_M))
			for step in count:
				var sample := a.lerp(b, (step + 0.5) / count)
				total += length / count
				if deck.bounds.has_point(sample) and _distance_to(deck.points, sample) <= deck.reach:
					inside += length / count
		if total > 0.0 and inside / total >= OVERLAP_RATIO:
			return true
	return false

func _distance_to(points: PackedVector2Array, sample: Vector2) -> float:
	var best := INF
	for index in range(1, points.size()):
		best = minf(best, sample.distance_to(Geometry2D.get_closest_point_to_segment(sample, points[index - 1], points[index])))
	return best
