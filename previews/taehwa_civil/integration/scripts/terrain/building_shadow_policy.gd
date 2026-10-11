extends RefCounted
class_name BuildingShadowPolicy

## 현재 공간 배치 안에서 실제 이웃을 확인한 저층 소형 건물만 그림자 계산에서 제외한다.
## 배치 경계를 넘어 이웃 수를 추정하지 않으므로 판정 누락 시 기본 그림자를 보존한다.
const RADIUS := 35.0
const MIN_NEIGHBORS := 6
const MAX_HEIGHT := 12.0
const MAX_SPAN := 16.0
const MAX_AREA := 140.0
const CampusPolicy = preload("res://scripts/terrain/campus_building_policy.gd")

static func split(buildings: Array) -> Dictionary:
	var cells: Dictionary = {}
	var positions: Dictionary = {}
	for i in buildings.size():
		var info := _small_position(buildings[i])
		if info.is_empty():
			continue
		var p: Vector2 = info.position
		positions[i] = p
		var key := Vector2i(floori(p.x / RADIUS), floori(p.y / RADIUS))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	var dense: Array = []
	var regular: Array = []
	for i in buildings.size():
		var count := 0
		if positions.has(i):
			var p: Vector2 = positions[i]
			var key := Vector2i(floori(p.x / RADIUS), floori(p.y / RADIUS))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for j in cells.get(key + Vector2i(dx, dz), []):
						if j != i and p.distance_squared_to(positions[j]) <= RADIUS * RADIUS:
							count += 1
		if count >= MIN_NEIGHBORS:
			dense.append(buildings[i])
		else:
			regular.append(buildings[i])
	return {"regular": regular, "dense": dense}

static func _small_position(b: Dictionary) -> Dictionary:
	if b.has("campus_site") or b.has("campus_role") or b.has("round") or b.get("landmark", false) or b.get("_campus_art_candidate", false):
		return {}
	if CampusPolicy.is_campus_candidate(b):
		return {}
	var polygon: Array = b.get("polygon", [])
	var size: Array = b.get("size", [10.0, 10.0, 10.0])
	var height := float(b.get("height", size[1]))
	if polygon.size() < 3:
		height = float(size[1]) if float(size[1]) > 4.0 else 9.0
	if height > MAX_HEIGHT:
		return {}
	var center: Array = b.get("center", [0.0, 0.0, 0.0])
	var p := Vector2(float(center[0]), float(center[2]))
	var span := Vector2(float(size[0]), float(size[2]))
	if polygon.size() >= 3:
		var lo := Vector2(float(polygon[0][0]), float(polygon[0][1]))
		var hi := lo
		p = Vector2.ZERO
		for point in polygon:
			var v := Vector2(float(point[0]), float(point[1]))
			lo = lo.min(v)
			hi = hi.max(v)
			p += v
		p /= float(polygon.size())
		span = hi - lo
	if maxf(span.x, span.y) >= MAX_SPAN or span.x * span.y > MAX_AREA:
		return {}
	return {"position": p}
