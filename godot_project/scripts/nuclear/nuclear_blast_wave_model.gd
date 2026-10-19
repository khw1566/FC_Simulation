extends RefCounted
class_name NuclearBlastWaveModel

## 충격파 전면 반경-시간 표를 폭발 시 한 번 적분한다.
## 과압은 Kinney-Graham 구형 폭풍 경험식, 전면 속도는 랭킨-위고니오 관계 U = c0 sqrt(1 + 6/7 dp/P0)를 쓴다.
## 핵폭발 에너지의 약 50%가 폭풍으로 가고, 지면 근처 폭발의 반사로 1.6배 증폭된다고 본다.

const SOUND_SPEED := 340.0
const SAMPLE_COUNT := 384
const START_RADIUS := 4.0
const END_RADIUS := 150000.0
const BLAST_FRACTION := 0.5
const SURFACE_REFLECTION := 1.6

var _mass_root := 1.0
var _radii := PackedFloat64Array()
var _times := PackedFloat64Array()
var _log_ratio := 1.0

func _init(kilotons: float) -> void:
	var tnt_kg := maxf(kilotons, 0.001) * 1.0e6 * BLAST_FRACTION * SURFACE_REFLECTION
	_mass_root = pow(tnt_kg, 1.0 / 3.0)
	_log_ratio = log(END_RADIUS / START_RADIUS)
	_build_table()

## 반경(m)에서의 최대 과압 / 대기압 비
func overpressure_ratio(radius: float) -> float:
	var z := maxf(radius, 0.01) / _mass_root
	var num := 808.0 * (1.0 + pow(z / 4.5, 2.0))
	var den := sqrt((1.0 + pow(z / 0.048, 2.0)) * (1.0 + pow(z / 0.32, 2.0)) * (1.0 + pow(z / 1.35, 2.0)))
	return num / den

func shock_speed(radius: float) -> float:
	return SOUND_SPEED * sqrt(1.0 + 6.0 / 7.0 * overpressure_ratio(radius))

func radius_at(time: float) -> float:
	if time <= _times[0]:
		return START_RADIUS * clampf(time / maxf(_times[0], 0.000001), 0.0, 1.0)
	var last := SAMPLE_COUNT - 1
	if time >= _times[last]:
		return END_RADIUS + SOUND_SPEED * (time - _times[last])
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _times[mid] <= time:
			lo = mid
		else:
			hi = mid
	var k := (time - _times[lo]) / maxf(_times[hi] - _times[lo], 0.0000001)
	return lerpf(_radii[lo], _radii[hi], k)

## 전면이 반경(m)에 도달하는 시각(s)
func arrival_time(radius: float) -> float:
	if radius <= START_RADIUS:
		return _times[0] * maxf(radius, 0.0) / START_RADIUS
	if radius >= END_RADIUS:
		return _times[SAMPLE_COUNT - 1] + (radius - END_RADIUS) / SOUND_SPEED
	var f := log(radius / START_RADIUS) / _log_ratio * float(SAMPLE_COUNT - 1)
	var i := mini(int(f), SAMPLE_COUNT - 2)
	return lerpf(_times[i], _times[i + 1], f - float(i))

## 과압비가 목표값으로 떨어지는 반경(m)
func radius_for_overpressure(ratio: float) -> float:
	var lo := log(START_RADIUS)
	var hi := log(END_RADIUS)
	for _i in range(40):
		var mid := (lo + hi) * 0.5
		if overpressure_ratio(exp(mid)) > ratio:
			lo = mid
		else:
			hi = mid
	return exp((lo + hi) * 0.5)

func _build_table() -> void:
	_radii.resize(SAMPLE_COUNT)
	_times.resize(SAMPLE_COUNT)
	var prev_r := START_RADIUS
	var prev_inv := 1.0 / shock_speed(prev_r)
	var t := prev_r * prev_inv
	_radii[0] = prev_r
	_times[0] = t
	for i in range(1, SAMPLE_COUNT):
		var r := START_RADIUS * exp(_log_ratio * float(i) / float(SAMPLE_COUNT - 1))
		var inv := 1.0 / shock_speed(r)
		t += (r - prev_r) * 0.5 * (inv + prev_inv)
		_radii[i] = r
		_times[i] = t
		prev_r = r
		prev_inv = inv
