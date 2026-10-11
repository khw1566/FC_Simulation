extends RefCounted
class_name AtmosphereStateModel

## 국제표준대기(ISA) 기반 고도별 기상 및 대기역학 계산 모델
## 비행 모델(Flight Model), 공기역학, 마하수, 동압 계산의 핵심 데이터 구조체

const SurfaceClimateModelClass = preload("res://scripts/models/surface_climate_model.gd")

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

## 특정 고도의 대기 상태 계산기
## 지상값은 SurfaceClimateModel(울산 평년값 + 계절·시각·날씨 보정)에서 받고, 고도 보정은 표준 감률을 따른다.
static func calculate_at_altitude(alt_m: float, ground_speed_ms: float, base_weather_type: int = 2, hour: float = -1.0) -> RefCounted:
	var state = load("res://scripts/models/atmosphere_state_model.gd").new()
	var surface = SurfaceClimateModelClass.calculate(base_weather_type, hour)
	state.altitude_m = alt_m
	state.altitude_ft = alt_m * 3.28084
	state.weather_name = surface.weather_name
	var z := maxf(alt_m, 0.0)
	var z_km := z / 1000.0

	# 1. 대류권 기온 감률: 100m당 -0.65℃ (11,000m 이후 등온층)
	var lapse_rate: float = 0.0065
	state.temperature_c = surface.temperature_c - minf(z, 11000.0) * lapse_rate
	state.temperature_k = state.temperature_c + 273.15

	# 2. 기압 공식 (Barometric Formula), 해면기압은 계절·날씨 반영값
	var t0_k: float = surface.temperature_c + 273.15
	var p11: float = surface.sea_level_pressure_hpa * pow(maxf(1.0 - (lapse_rate * minf(z, 11000.0)) / t0_k, 0.0001), 5.25588)
	state.pressure_hpa = p11 if z <= 11000.0 else p11 * exp(-0.000157 * (z - 11000.0))

	# 3. 공기 밀도 (이상기체 상태방정식, 건조공기 R = 287.058)
	state.air_density = (state.pressure_hpa * 100.0) / (287.058 * state.temperature_k)

	# 4. 이슬점·습도: 혼합층에서 이슬점 1.8℃/km 감소, 1.5km 이상 자유대기는 추가 건조
	var dew: float = surface.dew_point_c - 1.8 * minf(z_km, 1.5) - 4.0 * maxf(z_km - 1.5, 0.0)
	dew = minf(dew, state.temperature_c - 0.1)
	var rh := SurfaceClimateModelClass.relative_humidity_from(state.temperature_c, dew)
	# 구름층 내부 포화: 운저는 상승응결고도(LCL ≈ 125 × 기온-이슬점 차)
	var cloud := _cloud_layer(base_weather_type, surface.temperature_c - surface.dew_point_c)
	if z >= cloud.x and z <= cloud.y:
		rh = maxf(rh, cloud.z)
	state.relative_humidity = clampf(rh, 3.0, 100.0)
	state.dew_point_c = minf(SurfaceClimateModelClass.dew_point_from(state.temperature_c, state.relative_humidity), state.temperature_c)

	# 5. 바람: 지표 마찰층(0~1km) 멱법칙 증가 + 에크만 우편향, 상층은 계절 제트기류(서풍)로 수렴
	var v_surface: float = surface.wind_speed_ms
	var v_1km := v_surface * pow(1000.0 / 10.0, 0.14)
	var season := cos(surface.month_position / 12.0 * TAU) # 1월 = 1, 7월 = -1
	var jet_speed := 42.0 + 23.0 * season # 겨울 약 65m/s, 여름 약 19m/s
	var speed: float
	if z <= 1000.0:
		speed = v_surface * pow(maxf(z, 10.0) / 10.0, 0.14)
	else:
		speed = lerpf(v_1km, jet_speed, smoothstep(1000.0, 11000.0, z))
		if z > 12000.0:
			speed *= exp(-(z - 12000.0) / 6000.0)
	state.wind_speed_ms = speed
	state.wind_speed_knot = speed * 1.94384
	var dir_boundary: float = surface.wind_direction_deg + 20.0 * minf(z / 1000.0, 1.0)
	var jet_dir := 280.0 if season > 0.0 else 260.0
	state.wind_direction_deg = fposmod(SurfaceClimateModelClass.lerp_angle_deg(dir_boundary, jet_dir, smoothstep(1000.0, 7000.0, z)), 360.0)

	# 풍향은 불어오는 방향. 월드 축은 (동, 위, -북)이므로 바람이 향하는 속도 벡터로 변환한다.
	var rad: float = deg_to_rad(state.wind_direction_deg)
	state.wind_vector = Vector3(-sin(rad), 0.0, cos(rad)) * state.wind_speed_ms

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

## 날씨별 구름층 [운저 m, 운정 m, 층내 최소 습도 %]
static func _cloud_layer(weather_type: int, spread_c: float) -> Vector3:
	var base := clampf(125.0 * spread_c, 150.0, 2500.0)
	match weather_type:
		1: return Vector3(7500.0, 10500.0, 70.0)
		2: return Vector3(base, base + 800.0, 92.0)
		3: return Vector3(base, base + 1500.0, 97.0)
		4: return Vector3(0.0, 150.0, 99.0)
		5: return Vector3(minf(base, 600.0), 4500.0, 97.0)
		6: return Vector3(minf(base, 800.0), 11000.0, 97.0)
	return Vector3(-1.0, -1.0, 0.0)
