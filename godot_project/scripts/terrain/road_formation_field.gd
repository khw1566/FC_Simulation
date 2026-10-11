extends RefCounted
class_name RoadFormationField

## 메시 작업별 작은 공간 색인과 높이 캐시. 정점마다 청크 전체 도로를 검색하지 않는다.
const CELL := 16.0
var _grader: RefCounted
var _buckets: Dictionary = {}
var _heights: Dictionary = {}

func configure(grader: RefCounted, cells: Dictionary) -> void:
	_grader = grader
	var seen: Dictionary = {}
	for entries in cells.values():
		for s in entries:
			var identity: int = s.id
			if seen.has(identity):
				continue
			seen[identity] = true
			for z in range(floori(s.lower.y/CELL),floori(s.upper.y/CELL)+1):
				for x in range(floori(s.lower.x/CELL),floori(s.upper.x/CELL)+1):
					var key := Vector2i(x,z)
					if not _buckets.has(key):
						_buckets[key] = []
					_buckets[key].append(s)

func corrected_height(point: Vector3, _unused: Array = []) -> float:
	if _heights.has(point):
		return _heights[point]
	var candidates: Array = _buckets.get(Vector2i(floori(point.x/CELL),floori(point.z/CELL)),[])
	var value: float = point.y if candidates.is_empty() else _grader.corrected_height(point,candidates)
	_heights[point] = value
	return value
