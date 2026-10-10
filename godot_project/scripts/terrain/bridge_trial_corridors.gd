extends RefCounted
class_name BridgeTrialCorridors

## 태화강 조사 교량 시범 배치의 상판 영역. 상판과 나란히 겹치는 범용 교량 도로 구간을 잘라내고,
## 상판 위에 잘못 잡힌 건물(울산교 보행교 천막 등)을 생성하지 않는다.
## 도로 자료에 OSM ID가 없는 지도가 있으므로 형상으로 판정한다.

const RoadClassifier = preload("res://scripts/terrain/road_segment_classifier.gd")
const PATH := "res://assets/generated/taehwa_bridge_trial/placements.json"
const ROAD_MARGIN_M := 6.0
const BUILDING_MARGIN_M := 4.0
const BUILDING_END_INSET_M := 30.0
const PARALLEL_COS := 0.85
const SAMPLE_STEP_M := 5.0
const MIN_PIECE_M := 3.0

var osm_ids: Dictionary = {}
var _decks: Array[Dictionary] = []

func configure(map) -> void:
	_decks.clear()
	osm_ids.clear()
	if map == null or not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		return
	for entry in data.get("placements", []):
		if not entry is Dictionary or not _inside(entry.lonlat_start, map) or not _inside(entry.lonlat_end, map):
			continue
		var a := _world_xz(entry.lonlat_start, map)
		var b := _world_xz(entry.lonlat_end, map)
		if a.distance_to(b) < 1.0:
			continue
		var half_width := float(entry.get("deck_width_m", 10.0)) * 0.5
		_decks.append({"center": (a + b) * 0.5, "dir": (b - a).normalized(), "half_length": a.distance_to(b) * 0.5, "half_width": half_width, "road_margin": float(entry.get("road_clip_margin_m", ROAD_MARGIN_M))})
		for osm_id in entry.get("osm_ids", []):
			osm_ids[str(osm_id)] = true

func is_empty() -> bool:
	return _decks.is_empty()

## 교량 판정 도로를 상판 밖 구간들로 나눈다. 겹치지 않으면 원본 하나를, 전부 겹치면 빈 배열을 돌려준다.
func clip_road(road: Dictionary) -> Array:
	var points: Array = road.get("points", [])
	if _decks.is_empty() or not RoadClassifier.tag_enabled(road, "bridge") or points.size() < 2:
		return [road]
	var pieces: Array = []
	var current: Array = []
	var clipped := false
	for index in range(1, points.size()):
		var p0: Array = points[index - 1]
		var p1: Array = points[index]
		var a := Vector2(float(p0[0]), float(p0[p0.size() - 1]))
		var b := Vector2(float(p1[0]), float(p1[p1.size() - 1]))
		var count := maxi(1, ceili(a.distance_to(b) / SAMPLE_STEP_M))
		var direction := (b - a).normalized() if a.distance_to(b) > 0.01 else Vector2.ZERO
		for step in count + 1:
			if step == 0 and index > 1:
				continue
			var t := float(step) / count
			var xz := a.lerp(b, t)
			if _on_deck(xz, direction, -1.0, 0.0):
				clipped = true
				_flush(pieces, current)
				current = []
			else:
				current.append(_lerp_point(p0, p1, t))
	_flush(pieces, current)
	if not clipped:
		return [road]
	var result: Array = []
	for index in pieces.size():
		var piece: Dictionary = road.duplicate()
		piece.erase("_geometry_key")
		piece["points"] = pieces[index]
		piece["id"] = "%s_clip%d" % [str(road.get("id", "road")), index]
		result.append(piece)
	return result

func replaces_building(world_x: float, world_z: float) -> bool:
	return _on_deck(Vector2(world_x, world_z), Vector2.ZERO, BUILDING_MARGIN_M, BUILDING_END_INSET_M)

func _on_deck(xz: Vector2, direction: Vector2, margin: float, end_inset: float) -> bool:
	for deck in _decks:
		var offset: Vector2 = xz - deck.center
		var along: float = offset.dot(deck.dir)
		if absf(along) > deck.half_length - end_inset:
			continue
		# margin이 음수이면 교량별 도로 제거 여유폭을 쓴다
		if absf(offset.dot(deck.dir.orthogonal())) > deck.half_width + (deck.road_margin if margin < 0.0 else margin):
			continue
		if direction != Vector2.ZERO and absf(direction.dot(deck.dir)) < PARALLEL_COS:
			continue
		return true
	return false

static func _flush(pieces: Array, current: Array) -> void:
	if current.size() < 2:
		return
	var length := 0.0
	for index in range(1, current.size()):
		length += Vector2(current[index][0], current[index][2]).distance_to(Vector2(current[index - 1][0], current[index - 1][2]))
	if length >= MIN_PIECE_M:
		pieces.append(current)

static func _lerp_point(p0: Array, p1: Array, t: float) -> Array:
	var out: Array = []
	for axis in p0.size():
		out.append(lerpf(float(p0[axis]), float(p1[axis]), t))
	return out

static func _inside(lonlat: Array, map) -> bool:
	var lon := float(lonlat[0])
	var lat := float(lonlat[1])
	return lon >= map.bbox_west and lon <= map.bbox_east and lat >= map.bbox_south and lat <= map.bbox_north

static func _world_xz(lonlat: Array, map) -> Vector2:
	var size: float = map.world_size_meters
	return Vector2(((float(lonlat[0]) - map.bbox_west) / (map.bbox_east - map.bbox_west) - 0.5) * size,
		((map.bbox_north - float(lonlat[1])) / (map.bbox_north - map.bbox_south) - 0.5) * size)
