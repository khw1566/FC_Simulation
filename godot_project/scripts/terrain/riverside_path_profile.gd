extends RefCounted

## 접속점 배열로 이어진 보도의 연속 높이 프로파일. 이웃 조각이 접속점 높이를 공유하므로 단차가 없고,
## 각 조각의 전체 폭이 지형 위에 오도록 접속점을 올린다. 곡선 선형도 접속점마다 방향이 바뀔 뿐 같다.

const SAMPLE_STEP_M := 1.5

## points: 월드 XZ 접속점. 반환값은 접속점별 높이다.
static func node_heights(points: PackedVector2Array, half_width_m: float, clearance_m: float, elevation: Callable) -> PackedFloat64Array:
	var count := points.size()
	var heights := PackedFloat64Array()
	heights.resize(count)
	for k in range(count):
		heights[k] = _max_across(points[k], _node_normal(points, k), half_width_m, elevation) + clearance_m
	for k in range(count - 1):
		var a := points[k]
		var b := points[k + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var direction := (b - a) / length
		var normal := Vector2(direction.y, -direction.x)
		var steps := maxi(2, ceili(length / SAMPLE_STEP_M))
		var deficit := 0.0
		for s in range(1, steps):
			var t := float(s) / steps
			var ground := _max_across(a.lerp(b, t), normal, half_width_m, elevation) + clearance_m
			deficit = maxf(deficit, ground - lerpf(heights[k], heights[k + 1], t))
		if deficit > 0.0:
			heights[k] += deficit
			heights[k + 1] += deficit
	return heights

## +Z 진행축 에셋 조각 하나를 두 접속점 사이에 맞추는 변환. overlap_m만큼 양 끝을 늘려 굽은 접속부 틈을 덮는다.
static func segment_transform(a: Vector3, b: Vector3, asset_length_m: float, overlap_m: float) -> Transform3D:
	var span := b - a
	var length := span.length()
	var basis := Basis.looking_at(-span / length, Vector3.UP)
	basis = basis * Basis.from_scale(Vector3(1.0, 1.0, (length + overlap_m * 2.0) / asset_length_m))
	return Transform3D(basis, (a + b) * 0.5)

static func _node_normal(points: PackedVector2Array, k: int) -> Vector2:
	var before := points[maxi(k - 1, 0)]
	var after := points[mini(k + 1, points.size() - 1)]
	var direction := (after - before).normalized()
	return Vector2(direction.y, -direction.x)

static func _max_across(point: Vector2, normal: Vector2, half_width_m: float, elevation: Callable) -> float:
	var best := -INF
	var steps := maxi(2, ceili(half_width_m * 2.0))
	for s in range(steps + 1):
		var p := point + normal * lerpf(-half_width_m, half_width_m, float(s) / steps)
		best = maxf(best, float(elevation.call(p.x, p.y)))
	return best
