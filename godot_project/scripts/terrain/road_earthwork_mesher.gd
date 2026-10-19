extends RefCounted
class_name RoadEarthworkMesher

## 노반이 닿는 지형 격자 칸을 품질별 고정 분할 수로 균일 세분화하고 정점 고도만 노반으로 보정한다.
## 모든 노반 칸과 이웃 청크가 같은 분할 수를 쓰므로 공유 변의 정점이 일치해 틈·T자 균열이 생기지 않는다.
## 도로 단면 절단·적응 세분화를 하지 않아 밀집 도심에서도 칸당 비용이 일정하다.
## 보정량이 허용치보다 작은 칸은 원래 두 삼각형을 그대로 출력한다.
const FLAT_TOLERANCE := 0.05

## corners: 지형 격자 칸의 (x,y), (x+1,y), (x,y+1), (x+1,y+1) 정점(청크 국소 좌표).
static func add_cell(surface: SurfaceTool, corners: Array, center: Vector3, field: RefCounted, split: int,
	rail_grader: RefCounted, rail_segments: Array, size: float) -> void:
	var v0: Vector3 = corners[0]
	var v1: Vector3 = corners[1]
	var v2: Vector3 = corners[2]
	var v3: Vector3 = corners[3]
	var n := maxi(1, split)
	var points := PackedVector3Array()
	points.resize((n + 1) * (n + 1))
	var changed := false
	for j in range(n + 1):
		var fz := float(j) / n
		for i in range(n + 1):
			var fx := float(i) / n
			# 원래 칸의 (x+1,y)-(x,y+1) 대각선 삼각형 보간을 따라 세분화 정점의 원지형 고도를 정한다.
			var y := v0.y + fx * (v1.y - v0.y) + fz * (v2.y - v0.y) if fx + fz <= 1.0 else v3.y + (1.0 - fx) * (v2.y - v3.y) + (1.0 - fz) * (v1.y - v3.y)
			var p := Vector3(lerpf(v0.x, v1.x, fx), y, lerpf(v0.z, v2.z, fz))
			var corrected: float = field.corrected_height(p + center)
			changed = changed or absf(corrected - y) > FLAT_TOLERANCE
			p.y = corrected
			points[j * (n + 1) + i] = p
	if not changed:
		_emit(surface, v0, v1, v2, center, rail_grader, rail_segments, size)
		_emit(surface, v1, v3, v2, center, rail_grader, rail_segments, size)
		return
	# 세분화 사각형도 같은 방향 대각선을 써서 원래 칸의 대각선과 경계가 일치한다.
	for j in range(n):
		for i in range(n):
			var q0 := points[j * (n + 1) + i]
			var q1 := points[j * (n + 1) + i + 1]
			var q2 := points[(j + 1) * (n + 1) + i]
			var q3 := points[(j + 1) * (n + 1) + i + 1]
			_emit(surface, q0, q1, q2, center, rail_grader, rail_segments, size)
			_emit(surface, q1, q3, q2, center, rail_grader, rail_segments, size)

static func _emit(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3,
	rail_grader: RefCounted, rail_segments: Array, size: float) -> void:
	if rail_grader and not rail_segments.is_empty():
		rail_grader.add_triangle(surface, a, b, c, center, rail_segments, size)
		return
	for p in [a, b, c]:
		surface.set_uv(Vector2(p.x, p.z) / size + Vector2(0.5, 0.5))
		surface.add_vertex(p)
