extends RefCounted
class_name SurfaceClimateModel

## 울산(태화강 둔치) 지상 기상 산출 모델
## 기상청 울산 평년값(1991~2020)을 계절 보간하고, 시각별 일변화와 현재 날씨 상태 보정을 적용한다.

# 월별 평균기온(℃), 일교차(℃), 평균 상대습도(%), 평균풍속(m/s), 주풍향(도), 해면기압(hPa)
const MONTH_TEMP_C := [2.6, 4.4, 8.6, 13.7, 18.2, 21.6, 25.3, 26.1, 22.0, 17.0, 10.9, 4.6]
const MONTH_RANGE_C := [10.5, 10.2, 9.8, 9.6, 8.9, 7.2, 6.0, 6.6, 7.0, 8.8, 9.8, 10.4]
const MONTH_RH := [47.0, 52.0, 57.0, 61.0, 67.0, 75.0, 80.0, 78.0, 74.0, 66.0, 58.0, 50.0]
const MONTH_WIND_MS := [3.1, 3.1, 3.0, 2.8, 2.5, 2.3, 2.4, 2.4, 2.4, 2.6, 2.8, 3.0]
const MONTH_WIND_DEG := [315.0, 315.0, 300.0, 250.0, 200.0, 190.0, 200.0, 180.0, 30.0, 330.0, 320.0, 315.0]
const MONTH_SLP_HPA := [1024.5, 1022.5, 1019.0, 1015.0, 1011.0, 1007.5, 1006.5, 1007.5, 1012.0, 1017.5, 1021.0, 1024.0]

# 날씨 상태별 보정 [일교차 배율, 기온 편차(℃), 풍속 배율, 기압 편차(hPa)]
const WEATHER_ADJUST := {
	0: [1.15, 0.3, 0.9, 3.0],    # CLEAR
	1: [1.0, 0.0, 1.0, 1.5],     # CIRRUS_FAIR
	2: [0.85, -0.3, 1.1, 0.0],   # PARTLY_CLOUDY
	3: [0.45, -1.0, 1.35, -3.0], # OVERCAST
	4: [0.3, -0.5, 0.35, 1.0],   # FOGGY
	5: [0.25, -2.5, 1.8, -7.0],  # RAIN
	6: [0.35, -3.5, 3.6, -14.0], # STORM
}

const WEATHER_NAMES := {
	0: "쾌청 (Clear)",
	1: "맑음/권운 (Cirrus Fair)",
	2: "구름 조금 (Partly Cloudy)",
	3: "흐림/덮개구름 (Overcast)",
	4: "짙은 안개 (Foggy)",
	5: "비 (Rain)",
	6: "뇌우 (Storm)",
}

const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var weather_type: int = 2
var weather_name: String = "구름 조금 (Partly Cloudy)"
var temperature_c: float = 15.0
var dew_point_c: float = 8.0
var relative_humidity: float = 60.0
var wind_speed_ms: float = 2.5
var wind_direction_deg: float = 315.0
var sea_level_pressure_hpa: float = 1013.25
var month_position: float = 0.0 # 0.0 = 1월 중순, 1.0 = 2월 중순 ...
var hour: float = 12.0

## 지상(해발 약 0~10m) 기상 계산
static func calculate(p_weather_type: int, p_hour: float = -1.0, p_month_position: float = -1.0, p_time_sec: float = -1.0) -> RefCounted:
	var s = load("res://scripts/models/surface_climate_model.gd").new()
	s.weather_type = clampi(p_weather_type, 0, 6)
	s.weather_name = WEATHER_NAMES[s.weather_type]
	s.hour = fposmod(p_hour, 24.0) if p_hour >= 0.0 else system_hour()
	s.month_position = p_month_position if p_month_position >= 0.0 else system_month_position()
	var t_sec: float = p_time_sec if p_time_sec >= 0.0 else Time.get_ticks_msec() / 1000.0
	var adj: Array = WEATHER_ADJUST[s.weather_type]

	# 1. 기온: 평년 일평균 + 일변화(최저 05:30, 최고 14:30) + 날씨 편차
	var mean_t := _seasonal(MONTH_TEMP_C, s.month_position)
	var half_range := _seasonal(MONTH_RANGE_C, s.month_position) * 0.5 * float(adj[0])
	s.temperature_c = mean_t + half_range * _diurnal_shape(s.hour) + float(adj[1])

	# 2. 이슬점: 평년 습도에서 얻은 이슬점을 날씨에 따라 가감 (하루 중 거의 일정)
	var mean_dew := dew_point_from(mean_t, _seasonal(MONTH_RH, s.month_position))
	var dew := mean_dew
	match s.weather_type:
		0: dew = mean_dew - 2.0
		1: dew = mean_dew - 1.0
		3: dew = mean_dew + 1.5
		4: dew = s.temperature_c - 0.3
		5: dew = s.temperature_c - 1.0
		6: dew = s.temperature_c - 0.8
	# 맑은 날 새벽 복사냉각 시 포화 근접, 그 외에도 과포화 금지
	s.dew_point_c = minf(dew, s.temperature_c - 0.2)
	s.relative_humidity = clampf(relative_humidity_from(s.temperature_c, s.dew_point_c), 5.0, 100.0)

	# 3. 바람: 계절 주풍 + 해륙풍(울산 해안은 동쪽) + 날씨 계통풍
	var base_speed := _seasonal(MONTH_WIND_MS, s.month_position)
	var base_dir := _seasonal_angle(s.month_position)
	var day_factor := clampf(sin((s.hour - 8.0) / 12.0 * PI), 0.0, 1.0) # 08~20시 주간 혼합
	var calm_sky: bool = s.weather_type <= 2
	if calm_sky:
		# 주간 동풍 계열 해풍, 야간 서풍 계열 약한 육풍
		if day_factor > 0.0:
			base_dir = lerp_angle_deg(base_dir, 100.0, day_factor * 0.6)
			base_speed += 1.2 * day_factor
		else:
			base_dir = lerp_angle_deg(base_dir, 280.0, 0.35)
	match s.weather_type:
		5: base_dir = lerp_angle_deg(base_dir, 60.0, 0.6) # 남해상 저기압 통과 시 북동풍
		6: base_dir = lerp_angle_deg(base_dir, 140.0 if s.month_position >= 5.0 and s.month_position <= 8.5 else 210.0, 0.7)
	# 주간 혼합층 발달로 낮 풍속 증가, 야간 감소
	var speed := base_speed * float(adj[2]) * (0.7 + 0.6 * day_factor)
	# 완만한 풍향·풍속 요동 (고정 숫자처럼 보이지 않도록)
	var gust := sin(t_sec * 0.37) * 0.6 + sin(t_sec * 0.11 + 1.3) * 0.4
	speed *= 1.0 + gust * (0.25 if s.weather_type >= 5 else 0.15)
	base_dir += sin(t_sec * 0.05) * 8.0 + sin(t_sec * 0.21 + 0.7) * 4.0
	s.wind_speed_ms = maxf(speed, 0.2)
	s.wind_direction_deg = fposmod(base_dir, 360.0)

	# 4. 해면기압: 계절 평년 + 날씨 편차 + 일변화(10시·22시 극대 반일주조)
	s.sea_level_pressure_hpa = _seasonal(MONTH_SLP_HPA, s.month_position) + float(adj[3]) + 0.8 * cos((s.hour - 10.0) / 12.0 * TAU)
	return s

## 마그누스 공식 기반 상대습도(%)
static func relative_humidity_from(temp_c: float, dew_c: float) -> float:
	return 100.0 * exp((17.625 * dew_c) / (243.04 + dew_c) - (17.625 * temp_c) / (243.04 + temp_c))

## 마그누스 공식 기반 이슬점(℃)
static func dew_point_from(temp_c: float, rh: float) -> float:
	var g := log(clampf(rh, 1.0, 100.0) / 100.0) + (17.625 * temp_c) / (243.04 + temp_c)
	return 243.04 * g / (17.625 - g)

static func lerp_angle_deg(from_deg: float, to_deg: float, weight: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(from_deg), deg_to_rad(to_deg), weight))

## 게임 시계(DayNightCycleService)를 날씨 관리자 또는 씬 트리에서 조회, 없으면 시스템 시각
static func resolve_hour(weather_manager: Node) -> float:
	if weather_manager:
		var cycle = weather_manager.get("day_night_service")
		if cycle and "current_time_hours" in cycle:
			return float(cycle.current_time_hours)
	return system_hour()

static func system_hour() -> float:
	var now := Time.get_time_dict_from_system()
	return float(now.hour) + float(now.minute) / 60.0

## 시스템 날짜를 월 단위 연속값으로 변환 (각 달 중순 = 정수)
static func system_month_position() -> float:
	var date := Time.get_date_dict_from_system()
	var m := int(date.month) - 1
	return float(m) + (float(date.day) - 0.5) / float(DAYS_IN_MONTH[m]) - 0.5

## 하루 기온 곡선: 05:30 최저(-1), 14:30 최고(+1), 오후 하강이 완만
static func _diurnal_shape(h: float) -> float:
	var t_min := 5.5
	var t_max := 14.5
	if h >= t_min and h <= t_max:
		return -cos((h - t_min) / (t_max - t_min) * PI)
	var since_max := fposmod(h - t_max, 24.0)
	var night_len := 24.0 - (t_max - t_min)
	return cos(since_max / night_len * PI)

static func _seasonal(table: Array, pos: float) -> float:
	var p := fposmod(pos, 12.0)
	var i0 := int(floorf(p)) % 12
	var i1 := (i0 + 1) % 12
	var f := p - floorf(p)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(float(table[i0]), float(table[i1]), f)

static func _seasonal_angle(pos: float) -> float:
	var p := fposmod(pos, 12.0)
	var i0 := int(floorf(p)) % 12
	var i1 := (i0 + 1) % 12
	return lerp_angle_deg(float(MONTH_WIND_DEG[i0]), float(MONTH_WIND_DEG[i1]), p - floorf(p))
