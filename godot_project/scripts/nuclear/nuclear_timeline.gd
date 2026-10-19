extends RefCounted
class_name NuclearTimeline

## 폭발 후 경과 시간에서 섬광·화구·버섯구름·지면 먼지·응결운의 규모를 계산한다.
## 섬광·화구 냉각·충격파는 실시간, 부력 대류(구름 상승·확산)는 convection_scale 배속으로 진행한다.
## 높이는 모두 폭심 지면 기준(m)이다.

const Catalog := preload("res://scripts/nuclear/nuclear_yield_catalog.gd")
const BlastModel := preload("res://scripts/nuclear/nuclear_blast_wave_model.gd")

var kilotons := 10.0
var convection_scale := 3.0
var burst_height := 0.0
var fireball_max := 0.0
var thermal_peak := 0.1
var light_radius := 1000.0
var cloud_top_final := 9000.0
var cloud_bottom_final := 5500.0
var cap_radius_final := 2500.0
var stabilize_time := 240.0
var surge_height_max := 200.0
var surge_radius_max := 2000.0
var wilson_life := 1.0
var wilson_start := 0.0
var blast: BlastModel

# 평가 결과
var cloud_time := 0.0
var age_ratio := 0.0
var flash := 0.0
var heat := 1.0
var fireball_radius := 0.0
var cap_height := 0.0
var cap_radius := 0.0
var cap_half_height := 0.0
var form := 0.0
var roll_phase := 0.0
var rise_speed := 0.0
var stem_radius := 0.0
var stem_top := 0.0
var shock_radius := 0.0
var shock_overpressure := 0.0
var shock_thickness := 10.0
var surge_radius := 0.0
var surge_height := 0.0
var surge_alpha := 0.0
var wilson_radius := 0.0
var wilson_alpha := 0.0
var pileus_alpha := 0.0
var collar_alpha := 0.0
var cloud_alpha := 1.0
var clear_radius := 0.0

func _init(preset: Dictionary, time_scale: float) -> void:
	kilotons = float(preset.kilotons)
	convection_scale = maxf(time_scale, 0.01)
	burst_height = Catalog.burst_height(kilotons)
	fireball_max = Catalog.fireball_max_radius(kilotons)
	thermal_peak = Catalog.thermal_peak_time(kilotons)
	light_radius = Catalog.flash_light_radius(kilotons)
	cloud_top_final = float(preset.cloud_top)
	cloud_bottom_final = float(preset.cloud_bottom)
	cap_radius_final = float(preset.cap_radius)
	stabilize_time = float(preset.stabilize)
	surge_height_max = Catalog.surge_height(kilotons)
	wilson_life = Catalog.wilson_lifetime(kilotons)
	blast = BlastModel.new(kilotons)
	# 지면 먼지는 과압이 대기압의 12% 이상인 범위까지 일어난다.
	surge_radius_max = blast.radius_for_overpressure(0.12)
	wilson_start = blast.arrival_time(fireball_max * 1.6)

## 실시간 경과 초(t)로 모든 규모를 갱신한다.
func evaluate(t: float) -> void:
	cloud_time = t * convection_scale
	var x := cloud_time / stabilize_time
	age_ratio = x
	flash = _flash_curve(t)
	fireball_radius = fireball_max * pow(clampf(t / (thermal_peak * 1.5), 0.0, 1.0), 0.4)
	heat = 1.0 / (1.0 + pow(t / (8.0 * thermal_peak), 1.3))

	var rise := _rise_curve(x)
	rise_speed = _rise_rate(x) * (cloud_top_final - burst_height) / stabilize_time
	var top := burst_height + fireball_radius + (cloud_top_final - burst_height - fireball_max) * rise
	var spread := 1.0 + 0.3 * clampf((x - 1.0) * 0.5, 0.0, 1.0)
	cap_radius = lerpf(fireball_radius, cap_radius_final, pow(rise, 1.3)) * spread
	cap_half_height = lerpf(fireball_radius, (cloud_top_final - cloud_bottom_final) * 0.5, pow(rise, 1.1))
	cap_height = maxf(top - cap_half_height, burst_height)
	form = smoothstep(0.02, 0.35, x)
	# 토러스 순환은 상승과 함께 3.5바퀴 돌고 안정화 후 천천히 멈춘다.
	roll_phase = TAU * (3.5 * rise + 0.25 * log(1.0 + maxf(x - 1.0, 0.0)))
	# 기둥은 화구 반경 절반에서 시작해 갓 반경의 약 1/4까지 굵어진다.
	stem_radius = lerpf(fireball_max * 0.5, cap_radius_final * 0.24, pow(rise, 0.7))
	stem_top = (cap_height - cap_half_height * 0.3) * smoothstep(0.0, 0.3, x)
	clear_radius = maxf(stem_radius * 2.4, cap_radius * 0.9 * smoothstep(0.05, 0.25, x))

	shock_radius = blast.radius_at(t)
	shock_overpressure = blast.overpressure_ratio(shock_radius)
	shock_thickness = clampf(shock_radius * 0.06, 15.0, 900.0)

	surge_radius = minf(shock_radius * 0.97, surge_radius_max)
	surge_height = surge_height_max * (0.25 + 0.75 * smoothstep(0.0, 0.5, x))
	# 먼지 파도는 기둥이 자라는 동안 가라앉아 근거리 시야를 오래 가리지 않는다.
	surge_alpha = smoothstep(fireball_max * 0.5, fireball_max * 1.2, shock_radius) * (1.0 - smoothstep(0.8, 2.5, x))

	var wilson_age := t - wilson_start
	wilson_radius = shock_radius * 0.94
	wilson_alpha = smoothstep(0.0, 0.25 * wilson_life, wilson_age) * (1.0 - smoothstep(0.4 * wilson_life, wilson_life, wilson_age))

	pileus_alpha = smoothstep(0.03, 0.08, x) * (1.0 - smoothstep(0.25, 0.5, x))
	collar_alpha = smoothstep(0.08, 0.2, x) * (1.0 - smoothstep(1.2, 2.5, x))
	cloud_alpha = 1.0 - smoothstep(2.5, 4.0, x)

## 구름 소멸까지 남은 실시간(s)이 없으면 true
func is_finished() -> bool:
	return age_ratio >= 4.0

## 화구 표면 온도에 해당하는 발광색(셰이더의 nv_heat_color와 같은 단계)
static func heat_color(h: float) -> Color:
	var c := Color(0.35, 0.05, 0.01).lerp(Color(0.95, 0.25, 0.04), smoothstep(0.05, 0.3, h))
	c = c.lerp(Color(1.0, 0.58, 0.18), smoothstep(0.3, 0.5, h))
	c = c.lerp(Color(1.0, 0.86, 0.55), smoothstep(0.5, 0.75, h))
	return c.lerp(Color(1.0, 0.98, 0.95), smoothstep(0.75, 0.95, h))

## 이중 섬광: 수 ms의 1차 펄스 뒤 열복사 곡선 P = 2τ²/(1+τ⁴)
func _flash_curve(t: float) -> float:
	var tau := t / thermal_peak
	var second := 2.0 * tau * tau / (1.0 + tau * tau * tau * tau)
	var first := exp(-t / 0.03) * 0.9
	return maxf(first, second)

## 빠르게 솟다가 안정화 고도에서 부드럽게 멈추는 상승 곡선
func _rise_curve(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 2.5)

func _rise_rate(x: float) -> float:
	return 2.5 * pow(1.0 - clampf(x, 0.0, 1.0), 1.5)
