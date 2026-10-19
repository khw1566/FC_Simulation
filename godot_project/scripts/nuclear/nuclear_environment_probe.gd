extends RefCounted
class_name NuclearEnvironmentProbe

## 태양·환경광·안개·습도·고도풍·기존 구름 덮개를 핵폭발 시각화 입력으로 모은다.
## 구름 관리자와 같은 원천(방향광, WorldEnvironment, 대기 상태 모델)을 읽어 기존 구름과 조명이 어긋나지 않게 한다.

const AtmosphereStateModelClass := preload("res://scripts/models/atmosphere_state_model.gd")
const SurfaceClimateModelClass := preload("res://scripts/models/surface_climate_model.gd")
const FALLBACK_WIND := Vector3(8.0, 0.0, 4.0)

var sun_light: DirectionalLight3D
var world_environment: WorldEnvironment
var weather_manager: Node
var cloud_manager: Node
var day_night_service: Node
## 3차원 바람장(WindFieldService). 핵폭발 대류 교란도 여기에 등록한다.
var wind_field: Node

var sun_direction := Vector3.UP
var sun_color := Color.WHITE
var ambient := Color(0.55, 0.6, 0.68)
var haze_color := Color(0.68, 0.76, 0.86)
var haze_density := 0.000028
var night := 0.0

func refresh() -> void:
	night = _night_weight()
	if sun_light:
		sun_direction = sun_light.global_transform.basis.z.normalized()
		sun_color = sun_light.light_color * minf(sun_light.light_energy, 2.0) if sun_light.visible else Color.BLACK
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		haze_color = env.fog_light_color
		haze_density = env.fog_density if env.fog_enabled else 0.0
	ambient = haze_color.lerp(Color(0.55, 0.62, 0.75), 0.4) * lerpf(0.95, 0.1, night)

## 고도(m)의 상대 습도(0~1)
func humidity_at(altitude: float) -> float:
	if not weather_manager or not ("current_weather" in weather_manager):
		return 0.6
	var weather_type := int(weather_manager.get("current_weather"))
	var hour: float = SurfaceClimateModelClass.resolve_hour(weather_manager)
	var state = AtmosphereStateModelClass.calculate_at_altitude(altitude, 0.0, weather_type, hour)
	return clampf(float(state.relative_humidity) / 100.0, 0.0, 1.0)

## 월드 위치의 바람 벡터(m/s, y는 연직 성분)
func wind_at(position: Vector3) -> Vector3:
	if wind_field and wind_field.has_method("sample"):
		return wind_field.sample(position)
	if cloud_manager and cloud_manager.has_method("sample_wind"):
		return cloud_manager.sample_wind(position.y)
	return FALLBACK_WIND

func cloud_decks() -> Array:
	if cloud_manager and cloud_manager.has_method("get_cloud_decks"):
		return cloud_manager.get_cloud_decks()
	return []

## 0(최고)~3(경량) 렌더 품질. 구름을 꺼도 폭발은 경량 품질로 그린다.
func render_quality() -> int:
	if cloud_manager and cloud_manager.has_method("get_cloud_quality"):
		return clampi(int(cloud_manager.get_cloud_quality()), 0, 3)
	return 1

func _night_weight() -> float:
	if not day_night_service or not ("current_time_hours" in day_night_service):
		return 0.0
	var hours := float(day_night_service.current_time_hours)
	var daylight := smoothstep(5.2, 7.8, hours) * (1.0 - smoothstep(17.0, 19.4, hours))
	return 1.0 - daylight
