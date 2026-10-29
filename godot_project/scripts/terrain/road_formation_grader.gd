extends RefCounted
class_name RoadFormationGrader

## 읽기 전용 공간 타일의 중심 고도로 절토·성토한다. 교량·터널·수계는 생성 시 제외한다.
const SourceSignature = preload("res://scripts/terrain/source_signature.gd")
const CELL := 512.0
const CACHE_LIMIT := 96
const POINT_CELL := 16.0
var enabled := false
var _folder := ""
var _tiles: Dictionary = {}
var _cache: Dictionary = {}
var _mutex := Mutex.new()

func configure(source: String) -> void:
	enabled = false
	_tiles.clear()
	_cache.clear()
	_folder = source.get_base_dir().path_join("road_formation")
	var path := _folder.path_join("index.json")
	if not FileAccess.file_exists(path):
		return
	var index = JSON.parse_string(FileAccess.get_file_as_string(path))
	var file := FileAccess.open(source, FileAccess.READ)
	if not index is Dictionary or not file or index.get("version", 0) != 1:
		return
	if not _matches(source,file.get_length(),int(index.source_size),int(index.source_modified),str(index.get("source_sha256",""))):
		push_warning("도로 노반 원본이 변경되어 지형 보정을 보류합니다.")
		return
	var height: String = index.height_source
	var height_file := FileAccess.open(height, FileAccess.READ)
	if not height_file or not _matches(height,height_file.get_length(),int(index.height_size),int(index.height_modified),str(index.get("height_sha256",""))):
		push_warning("도로 노반의 기준 지형이 변경되어 보정을 보류합니다.")
		return
	if index.has("water_source"):
		var water_path: String = index.water_source
		var water := FileAccess.open(water_path,FileAccess.READ)
		if not water or not _matches(water_path,water.get_length(),int(index.water_size),int(index.water_modified),str(index.water_sha256)):
			push_warning("도로 노반의 수계 기준이 변경되어 보정을 보류합니다.")
			return
	_tiles = index.tiles
	enabled = true

func _matches(path: String, length: int, expected_size: int, expected_time: int, expected_hash: String) -> bool:
	return SourceSignature.matches(path, length, expected_size, expected_time, expected_hash)

func _tile(key: String) -> PackedFloat32Array:
	return _entry(key).data

func _entry(key: String) -> Dictionary:
	_mutex.lock()
	var cached: Dictionary = _cache.get(key,{})
	_mutex.unlock()
	if not cached.is_empty():
		return cached
	# 파일 읽기·해시·공간 색인 생성은 잠금 밖에서 처리한다. 이미 캐시된 높이 조회를 막지 않는다.
	var result := PackedFloat32Array()
	var points: Dictionary = {}
	if _tiles.has(key):
		var entry: Dictionary = _tiles[key]
		var bytes := FileAccess.get_file_as_bytes(_folder.path_join(entry.file))
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(bytes)
		if bytes.size() == int(entry.count) * 36 and context.finish().hex_encode() == entry.sha256:
			result = bytes.to_float32_array()
			for offset in range(0,result.size(),9):
				var s := _decode(result,offset)
				for z in range(floori(s.lower.y/POINT_CELL),floori(s.upper.y/POINT_CELL)+1):
					for x in range(floori(s.lower.x/POINT_CELL),floori(s.upper.x/POINT_CELL)+1):
						var location := Vector2i(x,z)
						if not points.has(location):
							points[location] = []
						points[location].append(s)
	var loaded := {"data":result,"points":points}
	_mutex.lock()
	if _cache.has(key):
		loaded = _cache[key]
	else:
		if _cache.size() >= CACHE_LIMIT:
			_cache.erase(_cache.keys()[0])
		_cache[key] = loaded
	_mutex.unlock()
	return loaded

func _decode(data: PackedFloat32Array, offset: int) -> Dictionary:
	var a := Vector3(data[offset],data[offset+2],data[offset+1])
	var b := Vector3(data[offset+3],data[offset+5],data[offset+4])
	var half := data[offset+6]
	var blend := data[offset+7]
	var lower := Vector2(a.x,a.z).min(Vector2(b.x,b.z))-Vector2.ONE*(half+blend)
	var upper := Vector2(a.x,a.z).max(Vector2(b.x,b.z))+Vector2.ONE*(half+blend)
	return {"id":int(data[offset+8]),"a":a,"b":b,"half":half,"blend":blend,"lower":lower,"upper":upper}

func _point_candidates(p: Vector3) -> Array:
	var key := "%d,%d" % [floori(p.x/CELL),floori(p.z/CELL)]
	var entry := _entry(key)
	var nearby: Array = entry.get("points",{}).get(Vector2i(floori(p.x/POINT_CELL),floori(p.z/POINT_CELL)),[])
	return nearby

func segments(bounds: Rect2) -> Array:
	var found: Dictionary = {}
	if not enabled:
		return []
	for z in range(floori(bounds.position.y/CELL), floori(bounds.end.y/CELL)+1):
		for x in range(floori(bounds.position.x/CELL), floori(bounds.end.x/CELL)+1):
			var data := _tile("%d,%d" % [x,z])
			for offset in range(0, data.size(), 9):
				var identity := int(data[offset+8])
				if found.has(identity):
					continue
				var s := _decode(data,offset)
				if bounds.intersects(Rect2(s.lower,s.upper-s.lower),true):
					found[identity] = s
	return found.values()

func cells(origin: Vector2, size: float, resolution: int) -> Dictionary:
	var result: Dictionary = {}
	var step := size / resolution
	for segment in segments(Rect2(origin, Vector2.ONE*size)):
		var lower: Vector2 = (segment.lower-origin)/step
		var upper: Vector2 = (segment.upper-origin)/step
		for z in range(maxi(0,floori(lower.y)), mini(resolution,floori(upper.y)+1)):
			for x in range(maxi(0,floori(lower.x)), mini(resolution,floori(upper.x)+1)):
				var key := Vector2i(x,z)
				if not result.has(key):
					result[key] = []
				result[key].append(segment)
	return result

func corrected_height(point: Vector3, candidates: Array = []) -> float:
	if not enabled:
		return point.y
	if candidates.is_empty():
		candidates = _point_candidates(point)
	var best := INF
	var result := point.y
	var p := Vector2(point.x,point.z)
	for s in candidates:
		var a: Vector3 = s.a
		var b: Vector3 = s.b
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf((p-Vector2(a.x,a.z)).dot(delta)/maxf(delta.length_squared(),.001),0.0,1.0)
		var distance := p.distance_to(Vector2(a.x,a.z)+delta*t)
		var score: float = distance/maxf(float(s.half),.5)
		if distance > float(s.half)+float(s.blend) or score >= best:
			continue
		best = score
		var weight := 1.0-smoothstep(float(s.half),float(s.half)+float(s.blend),distance)
		result = lerpf(point.y,lerpf(a.y,b.y,t),weight)
	return result
