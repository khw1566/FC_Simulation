extends RefCounted
class_name AtmosphereStateModel

## 국제표준대기(ISA) 기반 고도별 기상 및 대기역학 계산 모델
## 비행 모델(Flight Model), 공기역학, 마하수, 동압 계산의 핵심 데이터 구조체

# 1. 고도 및 기본 측정치
var altitude_m: float = 0.0          # 지오포텐셜 고도 (m)
var altitude_ft: float = 0.0         # 피트 고도 (ft)
var weather_name: String = "맑음"     # 현재 기본 기상 상태

# 2. 열역학 및 대기 상태
var temperature_c: float = 15.0      # 기온 (섭씨 ℃)
var temperature_k: float = 288.15    # 절대온도 (캘빈 K)
var pressure_hpa: float = 1013.25    # 기압 (hPa / mb)
var air_density: float = 1.225       # 공기 밀도 (kg/m³)
var relative_humidity: float = 50.0  # 상대 습도 (%)
var dew_point_c: float = 4.8         # 이슬점 온도 (℃)

# 3. 풍향 및 바람 벡터
var wind_speed_ms: float = 0.0       # 풍속 (m/s)
var wind_speed_knot: float = 0.0     # 풍속 (Knot)
var wind_direction_deg: float = 0.0  # 풍향 (도 0~360, 북풍=0, 동풍=90)
var wind_vector: Vector3 = Vector3.ZERO # 3D 바람 방향 벡터

# 4. 음속 및 마하수/공기역학 파라미터 (FM 연동용)
var speed_of_sound_ms: float = 340.29 # 음속 (m/s)
var mach_number: float = 0.0          # 현재 기체의 마하수
var dynamic_pressure_pa: float = 0.0  # 동압 q = 0.5 * rho * v^2 (Pa)
var true_airspeed_kmh: float = 0.0    # 진대기속도 (TAS, km/h)
var indicated_airspeed_kmh: float = 0.0 # 지시대기속도 (IAS, km/h)

## ISA 기반 특정 고도에서의 대기 상태 계산기
static func calculate_at_altitude(alt_m: float, ground_speed_ms: float, base_weather_type: int = 2) -> RefCounted:
	var state = load("res://scripts/models/atmosphere_state_model.gd").new()
	state.altitude_m = alt_m
	state.altitude_ft = alt_m * 3.28084

	# 기본 기상에 따른 지표면 기준치
	var base_temp_c := 18.0
	var base_humidity := 55.0
	var base_wind_speed := 4.5
	var base_wind_deg := 45.0 # 북동풍
	var w_name := "맑음"

	match base_weather_type:
		0: # CLEAR
			base_temp_c = 22.0
			base_humidity = 35.0
			base_wind_speed = 2.0
			w_name = "쾌청 (Clear)"
		1: # CIRRUS_FAIR
			base_temp_c = 19.0
			base_humidity = 45.0
			base_wind_speed = 3.5
			w_name = "맑음/권운 (Cirrus Fair)"
		2: # PARTLY_CLOUDY
			base_temp_c = 17.5
			base_humidity = 55.0
			base_wind_speed = 5.0
			w_name = "구름 조금 (Partly Cloudy)"
		3: # OVERCAST
			base_temp_c = 14.0
			base_humidity = 78.0
			base_wind_speed = 7.5
			w_name = "흐림/덮개구름 (Overcast)"
		4: # FOGGY
			base_temp_c = 11.0
			base_humidity = 95.0
			base_wind_speed = 1.5
			w_name = "짙은 안개 (Foggy)"
		5: # RAIN
			base_temp_c = 12.5
			base_humidity = 88.0
			base_wind_speed = 10.0
			w_name = "비 (Rain)"
		6: # STORM
			base_temp_c = 9.5
			base_humidity = 96.0
			base_wind_speed = 18.5
			base_wind_deg = 225.0
			w_name = "뇌우 (Storm)"

	state.weather_name = w_name

	# 1. 대류권 기온 감률: 100m당 -0.65℃ (고도 11,000m까지)
	var lapse_rate: float = 0.0065
	if alt_m <= 11000.0:
		state.temperature_c = base_temp_c - alt_m * lapse_rate
	else:
		state.temperature_c = base_temp_c - 11000.0 * lapse_rate # 성층권 하부 등온층 (-56.5℃)

	state.temperature_k = state.temperature_c + 273.15

	# 2. 기압 공식 (Barometric Formula)
	# P = P0 * (1 - L*h/T0)^(g*M/(R0*L))
	var t0_k: float = base_temp_c + 273.15
	if alt_m <= 11000.0:
		state.pressure_hpa = 1013.25 * pow(maxf(1.0 - (lapse_rate * alt_m) / t0_k, 0.0001), 5.25588)
	else:
		# 성층권 감쇄
		var p11: float = 1013.25 * pow(1.0 - (lapse_rate * 11000.0) / t0_k, 5.25588)
		state.pressure_hpa = p11 * exp(-0.000157 * (alt_m - 11000.0))

	# 3. 공기 밀도 (이상기체 상태방정식: rho = P / (R_specific * T))
	# R_specific for dry air = 287.058 J/(kg·K)
	var pressure_pa: float = state.pressure_hpa * 100.0
	state.air_density = pressure_pa / (287.058 * state.temperature_k)

	# 4. 상대 습도 및 이슬점 감률
	# 고도 상승에 따라 수증기압 감소로 습도 감소 (구름층 1,000~2,500m 부근 국소 상승 모사)
	var cloud_layer_boost: float = 0.0
	if alt_m >= 800.0 and alt_m <= 2800.0:
		cloud_layer_boost = sin((alt_m - 800.0) / 2000.0 * PI) * 22.0

	var altitude_humidity_factor: float = exp(-alt_m / 4500.0)
	state.relative_humidity = clampf(base_humidity * altitude_humidity_factor + cloud_layer_boost, 5.0, 99.0)
	# 마그누스 공식 간이 이슬점 근사: Td ≈ T - ((100 - RH)/5)
	state.dew_point_c = state.temperature_c - ((100.0 - state.relative_humidity) / 5.0)

	# 5. 고도별 풍속 및 제트기류 (Jet Stream & Wind Shear)
	# 지표 마찰층(0~500m) 탈출 후 고도에 비례하여 풍속 증가, 고고도(9,000m 부근) 제트기류 피크
	var alt_wind_factor: float = 1.0 + (alt_m / 1000.0) * 1.8
	if alt_m > 8000.0:
		alt_wind_factor += ((alt_m - 8000.0) / 2000.0) * 4.0
	state.wind_speed_ms = base_wind_speed * alt_wind_factor
	state.wind_speed_knot = state.wind_speed_ms * 1.94384
	# 고도 전단에 따른 풍향 회전(전향력/에크만 스파이럴 효과: 고도가 높을수록 우측으로 편향)
	var dir_veer: float = (alt_m / 1000.0) * 5.0
	state.wind_direction_deg = fmod(base_wind_deg + dir_veer, 360.0)

	var rad: float = deg_to_rad(state.wind_direction_deg)
	state.wind_vector = Vector3(-sin(rad), 0.0, -cos(rad)) * state.wind_speed_ms

	# 6. 음속 계산: a = sqrt(gamma * R * T), gamma=1.4, R=287.05 -> a ≈ 20.0468 * sqrt(T_K)
	state.speed_of_sound_ms = 20.0468 * sqrt(maxf(state.temperature_k, 1.0))

	# 7. 마하수, TAS, IAS, 동압 계산
	var tas_ms: float = ground_speed_ms # 간이 무풍 대비 기본 TAS (추후 벡터풍 결합 확장 가능)
	state.true_airspeed_kmh = tas_ms * 3.6
	state.mach_number = tas_ms / maxf(state.speed_of_sound_ms, 0.001)

	# 지시대기속도 IAS = TAS * sqrt(rho / rho0)
	state.indicated_airspeed_kmh = state.true_airspeed_kmh * sqrt(clampf(state.air_density / 1.225, 0.01, 1.5))
	# 동압 q = 0.5 * rho * v^2
	state.dynamic_pressure_pa = 0.5 * state.air_density * (tas_ms * tas_ms)

	return state
