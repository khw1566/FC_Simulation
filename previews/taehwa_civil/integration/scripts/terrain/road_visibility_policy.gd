extends RefCounted
class_name RoadVisibilityPolicy

## 좁은 도로부터 숨긴다. 짧은 공간 묶음으로 나눠 긴 도로의 중심점 컬링을 피한다.
const CELL := 256.0
const SMALL_RANGE := 1600.0
const MEDIUM_RANGE := 3500.0
const MAJOR_TYPES := ["motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link"]
const SMALL_TYPES := ["footway", "path", "steps", "track", "cycleway", "bridleway", "corridor"]

static func tier(road: Dictionary) -> String:
	var kind := str(road.get("type", ""))
	var width := float(road.get("width", 8.0))
	if kind in MAJOR_TYPES or width >= 9.0:
		return "major"
	if width <= 4.0 or (kind in SMALL_TYPES and width <= 6.0):
		return "small"
	return "medium"

static func distance(tier_name: String, view_range: float) -> float:
	if tier_name == "small":
		return minf(SMALL_RANGE, view_range)
	if tier_name == "medium":
		return minf(MEDIUM_RANGE, view_range)
	return view_range + 4500.0

static func pieces(points: Array[Vector3], heights: Array[float]) -> Array:
	var result: Array = []
	for i in range(points.size()-1):
		var midpoint := (points[i]+points[i+1])*.5
		var cell := Vector2i(floori(midpoint.x/CELL), floori(midpoint.z/CELL))
		if result.is_empty() or result[-1].cell != cell:
			var p: Array[Vector3] = [points[i],points[i+1]]
			var h: Array[float] = [heights[i],heights[i+1]]
			var piece := {"cell":cell,"points":p,"heights":h}
			if i > 0:
				piece["before"] = points[i-1]
			result.append(piece)
		else:
			result[-1].points.append(points[i+1])
			result[-1].heights.append(heights[i+1])
		if i+2 < points.size():
			result[-1]["after"] = points[i+2]
		else:
			result[-1].erase("after")
	return result
