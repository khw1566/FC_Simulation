extends "res://scripts/weather/wind_perturbation.gd"
class_name NuclearWindPerturbation

## 핵폭발 대류가 주변 바람장에 더하는 국지 벡터.
## 기둥 상승류, 지면 유입풍(후폭풍: 폭심으로 빨려 드는 바람), 갓 고도의 방사 유출을 합친다.
## params: ground, cap(월드 위치), cap_radius, cap_half, stem_radius, updraft(m/s), strength(0~1)

# 격자 간격(2.5km)보다 좁은 기둥은 칸 사이에서 사라지므로 최소 폭을 둔다.
const MIN_COLUMN_WIDTH := 2500.0

func bounds(params: Dictionary) -> AABB:
	var ground: Vector3 = params.ground
	var cap: Vector3 = params.cap
	var reach := _reach(params) * 2.5
	var center := Vector2(ground.x + cap.x, ground.z + cap.z) * 0.5
	var spread := Vector2(absf(cap.x - ground.x), absf(cap.z - ground.z)) * 0.5 + Vector2(reach, reach)
	var top := cap.y + float(params.cap_half) * 2.0 + 1000.0
	return AABB(Vector3(center.x - spread.x, ground.y - 200.0, center.y - spread.y), Vector3(spread.x * 2.0, top - ground.y + 200.0, spread.y * 2.0))

func vector_at(params: Dictionary, pos: Vector3) -> Vector3:
	var ground: Vector3 = params.ground
	var cap: Vector3 = params.cap
	var strength: float = params.strength
	var updraft: float = params.updraft
	var cap_radius: float = params.cap_radius
	var cap_half: float = maxf(params.cap_half, 100.0)
	var span := maxf(cap.y - ground.y, 1.0)
	var h := pos.y - ground.y
	var k := clampf(h / span, 0.0, 1.0)
	var axis := Vector2(ground.x, ground.z).lerp(Vector2(cap.x, cap.z), k)
	var off := Vector2(pos.x, pos.z) - axis
	var r := off.length()
	var dir := off / r if r > 1.0 else Vector2.ZERO
	var column := maxf(float(params.stem_radius) * 1.5, MIN_COLUMN_WIDTH)
	# 기둥 상승류: 갓 중심 위로 갓 반높이만큼까지
	var w := updraft * exp(-pow(r / column, 2.0)) * (1.0 - smoothstep(span, span + cap_half, h))
	# 지면 유입풍: 지면 근처에서 폭심 쪽으로
	var r_in := column * 2.0 + cap_radius * 0.4
	var inflow := -0.45 * updraft * _ring(r, r_in) * exp(-maxf(h, 0.0) / maxf(span * 0.15, 300.0))
	# 갓 고도 방사 유출
	var dy := (pos.y - cap.y) / cap_half
	var outflow := 0.5 * updraft * _ring(r, maxf(cap_radius, column)) * exp(-dy * dy)
	var radial := inflow + outflow
	return Vector3(dir.x * radial, w, dir.y * radial) * strength

func _reach(params: Dictionary) -> float:
	return maxf(maxf(float(params.cap_radius), float(params.stem_radius) * 4.0), MIN_COLUMN_WIDTH * 2.0)

## r0 근처에서 최대 1이 되는 고리 형태(r=0과 먼 곳에서 0)
static func _ring(r: float, r0: float) -> float:
	var x := r / maxf(r0, 1.0)
	return 2.33 * x * exp(-x * x)
