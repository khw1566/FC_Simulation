extends Control
class_name WeatherDetailsHUDView

## TAB 키로 토글되는 고도별 상세 기상 및 대기역학/FM HUD 뷰 (모노크롬 테마)

const AtmosphereStateModelClass = preload("res://scripts/models/atmosphere_state_model.gd")

@onready var panel_container: PanelContainer = $RootPanel
@onready var title_label: Label = $RootPanel/Margin/VBox/Header/TitleLabel
@onready var weather_state_val: Label = $RootPanel/Margin/VBox/Header/WeatherStateVal

# 1. 고도 및 열역학 그리드
@onready var val_alt_m: Label = $RootPanel/Margin/VBox/Grid/RowAlt/ValM
@onready var val_alt_ft: Label = $RootPanel/Margin/VBox/Grid/RowAlt/ValFt
@onready var val_temp: Label = $RootPanel/Margin/VBox/Grid/RowTemp/ValTemp
@onready var val_dew: Label = $RootPanel/Margin/VBox/Grid/RowTemp/ValDew
@onready var val_press: Label = $RootPanel/Margin/VBox/Grid/RowPress/ValPress
@onready var val_density: Label = $RootPanel/Margin/VBox/Grid/RowPress/ValDensity
@onready var val_humidity: Label = $RootPanel/Margin/VBox/Grid/RowHumidity/ValHumidity

# 2. 바람 및 대기 순환 그리드
@onready var val_wind_speed: Label = $RootPanel/Margin/VBox/Grid/RowWind/ValSpeed
@onready var val_wind_dir: Label = $RootPanel/Margin/VBox/Grid/RowWind/ValDir

# 3. 비행 역학(FM) 및 마하수 그리드
@onready var val_mach: Label = $RootPanel/Margin/VBox/RowMach/ValMach
@onready var val_sound: Label = $RootPanel/Margin/VBox/RowMach/ValSound
@onready var val_tas: Label = $RootPanel/Margin/VBox/RowAirspeed/ValTAS
@onready var val_ias: Label = $RootPanel/Margin/VBox/RowAirspeed/ValIAS
@onready var val_q: Label = $RootPanel/Margin/VBox/RowDynamicPressure/ValQ

var _is_hud_visible: bool = false

func _ready() -> void:
	visible = false

func toggle_visibility() -> void:
	set_hud_visible(!_is_hud_visible)

func set_hud_visible(p_visible: bool) -> void:
	_is_hud_visible = p_visible
	visible = _is_hud_visible

func update_atmosphere_data(data: RefCounted) -> void:
	if not visible or data == null:
		return

	if weather_state_val:
		weather_state_val.text = data.weather_name

	if val_alt_m:
		val_alt_m.text = "%5.0f m" % data.altitude_m
	if val_alt_ft:
		val_alt_ft.text = "(%6.0f ft)" % data.altitude_ft

	if val_temp:
		val_temp.text = "%+5.1f ℃" % data.temperature_c
	if val_dew:
		val_dew.text = "(이슬점: %+4.1f ℃)" % data.dew_point_c

	if val_press:
		val_press.text = "%6.1f hPa" % data.pressure_hpa
	if val_density:
		val_density.text = "%5.3f kg/m³" % data.air_density

	if val_humidity:
		val_humidity.text = "%4.1f %%" % data.relative_humidity

	if val_wind_speed:
		val_wind_speed.text = "%4.1f m/s (%3.0f kt)" % [data.wind_speed_ms, data.wind_speed_knot]
	if val_wind_dir:
		var cardinals := ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"]
		var c_idx := int(round(data.wind_direction_deg / 45.0)) % 8
		val_wind_dir.text = "%03.0f° [%s]" % [data.wind_direction_deg, cardinals[c_idx]]

	if val_mach:
		val_mach.text = "Mach %5.2f" % data.mach_number
	if val_sound:
		val_sound.text = "(음속: %4.0f m/s)" % data.speed_of_sound_ms

	if val_tas:
		val_tas.text = "%5.0f km/h" % data.true_airspeed_kmh
	if val_ias:
		val_ias.text = "(지시대기속도: %5.0f km/h)" % data.indicated_airspeed_kmh

	if val_q:
		val_q.text = "%7.1f Pa" % data.dynamic_pressure_pa
