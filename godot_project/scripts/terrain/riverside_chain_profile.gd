extends RefCounted

## 직선으로 이어진 보도 세그먼트의 연속 높이 프로파일. 접속점마다 하나의 높이를 공유하므로
## 이웃 세그먼트가 같은 높이에서 만나고, 세그먼트 전체 폭이 지형 위에 오도록 접속점을 올린다.

const SAMPLE_STEP_M := 1.5

var start := Vector2.ZERO
var direction := Vector2(0, 1)
var segment_length := 12.0
## 지도 투영 차이로 생기는 실제 세그먼트 간격 / 에셋 길이 비율
var stretch := 1.0
var heights: PackedFloat64Array = PackedFloat64Array()

## segments: chain_index 순서와 무관한 {xz: Vector2, index: int} 배열. 모두 같은 방향이어야 한다.
## 지도마다 위경도-미터 비율이 달라 실제 간격과 방향은 세그먼트 중심 위치에서 다시 구한다.
func build(segments: Array, yaw_degrees: float, length_m: float, half_width_m: float, clearance_m: float, elevation: Callable) -> void:
	var ordered := segments.duplicate()
	ordered.sort_custom(func(a, b): return a.index < b.index)
	direction = Vector2(sin(deg_to_rad(yaw_degrees)), cos(deg_to_rad(yaw_degrees)))
	segment_length = length_m
	var span := int(ordered[-1].index) - int(ordered[0].index)
	if span > 0:
		var delta: Vector2 = ordered[-1].xz - ordered[0].xz
		direction = delta.normalized()
		segment_length = delta.length() / span
	stretch = segment_length / length_m
	length_m = segment_length
	var first: Vector2 = ordered[0].xz
	start = first - direction * (length_m * 0.5) - direction * (float(ordered[0].index) * length_m)
	var count := int(ordered[-1].index) + 1
	heights.resize(count + 1)
	for k in range(count + 1):
		heights[k] = _max_across(start + direction * (k * length_m), Vector2(direction.y, -direction.x), half_width_m, elevation) + clearance_m
	var normal := Vector2(direction.y, -direction.x)
	for k in range(count):
		var deficit := 0.0
		var steps := maxi(2, ceili(length_m / SAMPLE_STEP_M))
		for s in range(steps + 1):
			var t := float(s) / steps
			var ground := _max_across(start + direction * ((k + t) * length_m), normal, half_width_m, elevation) + clearance_m
			deficit = maxf(deficit, ground - lerpf(heights[k], heights[k + 1], t))
		if deficit > 0.0:
			heights[k] += deficit
			heights[k + 1] += deficit

func yaw() -> float:
	return atan2(direction.x, direction.y)

func segment_center_y(index: int) -> float:
	return (heights[index] + heights[index + 1]) * 0.5

func segment_slope(index: int) -> float:
	return (heights[index + 1] - heights[index]) / segment_length

static func _max_across(point: Vector2, normal: Vector2, half_width_m: float, elevation: Callable) -> float:
	var best := -INF
	var steps := maxi(2, ceili(half_width_m * 2.0))
	for s in range(steps + 1):
		var p := point + normal * lerpf(-half_width_m, half_width_m, float(s) / steps)
		best = maxf(best, float(elevation.call(p.x, p.y)))
	return best
