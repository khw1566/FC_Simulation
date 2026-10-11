extends RefCounted

## 접속점 배열로 이어진 보도의 연속 높이·횡경사 프로파일. 이웃 조각이 접속점 높이를 공유해 단차가 없고,
## 조각을 지형의 횡경사만큼 옆으로 기울여 비탈에서 한쪽 가장자리가 뜨지 않게 한다.
## 조각 표면이 지면보다 낮아지는 곳이 있으면 그 조각의 두 접속점을 함께 올린다.

const SAMPLE_STEP_M := 1.5

## points: 월드 XZ 접속점. 반환값은 {"heights": 접속점 중심 높이, "slopes": 접속점 횡경사(오른쪽 +)}.
static func build(points: PackedVector2Array, half_width_m: float, clearance_m: float, elevation: Callable) -> Dictionary:
	var count := points.size()
	var heights := PackedFloat64Array()
	var slopes := PackedFloat64Array()
	heights.resize(count)
	slopes.resize(count)
	for k in range(count):
		var normal := _node_normal(points, k)
		var left := float(elevation.call(points[k].x - normal.x * half_width_m, points[k].y - normal.y * half_width_m))
		var right := float(elevation.call(points[k].x + normal.x * half_width_m, points[k].y + normal.y * half_width_m))
		slopes[k] = (right - left) / (2.0 * half_width_m)
		heights[k] = float(elevation.call(points[k].x, points[k].y)) + clearance_m
	for k in range(count - 1):
		var a := points[k]
		var b := points[k + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var direction := (b - a) / length
		var normal := Vector2(direction.y, -direction.x)
		var slope := (slopes[k] + slopes[k + 1]) * 0.5
		var steps := maxi(2, ceili(length / SAMPLE_STEP_M))
		var deficit := 0.0
		for s in range(steps + 1):
			var t := float(s) / steps
			var center := a.lerp(b, t)
			for side in [-1.0, 0.0, 1.0]:
				var offset: float = side * half_width_m
				var ground := float(elevation.call(center.x + normal.x * offset, center.y + normal.y * offset)) + clearance_m
				deficit = maxf(deficit, ground - (lerpf(heights[k], heights[k + 1], t) + slope * offset))
		if deficit > 0.0:
			heights[k] += deficit
			heights[k + 1] += deficit
	return {"heights": heights, "slopes": slopes}

## +Z 진행축 에셋 조각 하나를 두 접속점 사이에 맞추는 변환. cross_slope만큼 옆으로 기울이고,
## overlap_m만큼 양 끝을 늘려 굽은 접속부 틈을 덮는다.
static func segment_transform(a: Vector3, b: Vector3, cross_slope: float, asset_length_m: float, overlap_m: float) -> Transform3D:
	var span := b - a
	var length := span.length()
	var forward := span / length
	var flat := Vector2(forward.x, forward.z).normalized()
	var right := Vector3(flat.y, cross_slope, -flat.x).normalized()
	var up := forward.cross(right).normalized()
	right = up.cross(forward).normalized()
	var basis := Basis(right, up, forward * ((length + overlap_m * 2.0) / asset_length_m))
	return Transform3D(basis, (a + b) * 0.5)

static func _node_normal(points: PackedVector2Array, k: int) -> Vector2:
	var before := points[maxi(k - 1, 0)]
	var after := points[mini(k + 1, points.size() - 1)]
	var direction := (after - before).normalized()
	return Vector2(direction.y, -direction.x)
