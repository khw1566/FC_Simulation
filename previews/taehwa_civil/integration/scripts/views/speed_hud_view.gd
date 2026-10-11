extends Control
class_name SpeedHUDView

@onready var speed_value_label: Label = $PanelContainer/MarginContainer/HBoxContainer/SpeedVBox/SpeedValueLabel
@onready var altitude_value_label: Label = $PanelContainer/MarginContainer/HBoxContainer/AltitudeVBox/AltitudeValueLabel
@onready var gear_label: Label = $PanelContainer/MarginContainer/HBoxContainer/GearVBox/GearLabel
@onready var speed_progress_bar: ProgressBar = $PanelContainer/MarginContainer/HBoxContainer/SpeedVBox/SpeedProgressBar

var _current_gear: int = 1
var _max_gear: int = 4
var _current_accel: float = 50.0
var _current_altitude: float = 350.0
var _collision_status: String = "ON"
var _gravity_status: String = "OFF (비행)"
var _terrain_mode: String = "위성 피복 [T]"

var _current_mode_name: String = "디버그-비행"

func update_speed_display(speed_kmh: float, gear: int, max_gear: int, accel: float = 50.0, altitude_m: float = 0.0, gravity_enabled: bool = false, mode_name: String = "디버그-비행") -> void:
	_current_gear = gear
	_max_gear = max_gear
	_current_accel = accel
	_current_altitude = altitude_m
	_current_mode_name = mode_name
	_gravity_status = "ON (중력)" if gravity_enabled else "OFF (비행)"
	if speed_value_label:
		speed_value_label.text = "%4.0f km/h" % speed_kmh
	if altitude_value_label:
		altitude_value_label.text = "%4.1f m" % altitude_m
	_refresh_labels()
	if speed_progress_bar:
		var max_ref: float = 12240.0 if _current_mode_name == "디버그-비행" else 200.0
		speed_progress_bar.value = clampf(speed_kmh / max_ref * 100.0, 0.0, 100.0)

func update_collision_status(is_enabled: bool) -> void:
	_collision_status = "ON" if is_enabled else "OFF (노클립)"
	_refresh_labels()

func update_gravity_status(is_enabled: bool) -> void:
	_gravity_status = "ON (중력)" if is_enabled else "OFF (비행)"
	_refresh_labels()

func update_terrain_mode(is_simple: bool) -> void:
	_terrain_mode = "심플 등고선 [T]" if is_simple else "위성 피복 [T]"
	_refresh_labels()

func _refresh_labels() -> void:
	if gear_label:
		if _current_mode_name == "디버그-지상":
			gear_label.text = "[%s] G%d/%d | 즉발 속도 [F1]" % [
				_current_mode_name, _current_gear, _max_gear
			]
		else:
			gear_label.text = "[%s] G%d/%d | %.0f m/s² [F1]" % [
				_current_mode_name, _current_gear, _max_gear, _current_accel
			]
