extends Node
class_name WeatherDetailsHUDController

const AtmosphereStateModelClass = preload("res://scripts/models/atmosphere_state_model.gd")
const SurfaceClimateModelClass = preload("res://scripts/models/surface_climate_model.gd")

## 기상 상세 정보 HUD(TAB 키 토글) 제어 컨트롤러
## 플레이어의 고도 및 속도, 날씨 상태를 실시간 수신하여 ISA 대기역학 모델 계산 및 뷰 동기화

@export var hud_view: Control
@export var player_node: CharacterBody3D
@export var weather_manager: Node3D

var _current_weather_type: int = 2 # 기본: PARTLY_CLOUDY
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1 # 10Hz 주기로 대기역학 모델 갱신

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if not hud_view or not hud_view.visible:
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_refresh_atmosphere_data()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			# TAB 키 입력 시 기상 상세 HUD 표시 여부 토글
			if hud_view and hud_view.has_method("toggle_visibility"):
				hud_view.call("toggle_visibility")
				if hud_view.visible:
					_refresh_atmosphere_data()
			get_viewport().set_input_as_handled()

func _refresh_atmosphere_data() -> void:
	var alt_m: float = 0.0
	var speed_ms: float = 0.0

	if player_node:
		alt_m = player_node.global_position.y
		speed_ms = player_node.velocity.length()

	var w_type: int = _current_weather_type
	if weather_manager:
		w_type = int(weather_manager.get("current_weather"))

	var hour: float = SurfaceClimateModelClass.resolve_hour(weather_manager)
	var data = AtmosphereStateModelClass.calculate_at_altitude(alt_m, speed_ms, w_type, hour)

	if hud_view and hud_view.has_method("update_atmosphere_data"):
		hud_view.call("update_atmosphere_data", data)
