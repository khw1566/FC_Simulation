extends Node
class_name SpeedHUDController

@export var speed_hud_view: Control
@export var player_node: CharacterBody3D

func _ready() -> void:
	if player_node and speed_hud_view:
		if player_node.has_signal("speed_changed"):
			player_node.speed_changed.connect(_on_speed_changed)
		if player_node.has_signal("collision_toggled"):
			player_node.collision_toggled.connect(_on_collision_toggled)
		if player_node.has_signal("gravity_toggled"):
			player_node.gravity_toggled.connect(_on_gravity_toggled)
		if player_node.has_signal("terrain_mode_toggled"):
			player_node.terrain_mode_toggled.connect(_on_terrain_mode_toggled)

func _on_speed_changed(speed_kmh: float, gear: int, max_gear: int, accel: float = 50.0, altitude_m: float = 0.0, gravity_enabled: bool = false, mode_name: String = "디버그-비행") -> void:
	if speed_hud_view and speed_hud_view.has_method("update_speed_display"):
		speed_hud_view.update_speed_display(speed_kmh, gear, max_gear, accel, altitude_m, gravity_enabled, mode_name)

func _on_collision_toggled(is_enabled: bool) -> void:
	if speed_hud_view and speed_hud_view.has_method("update_collision_status"):
		speed_hud_view.update_collision_status(is_enabled)

func _on_gravity_toggled(is_enabled: bool) -> void:
	if speed_hud_view and speed_hud_view.has_method("update_gravity_status"):
		speed_hud_view.update_gravity_status(is_enabled)

func _on_terrain_mode_toggled(is_simple: bool) -> void:
	if speed_hud_view and speed_hud_view.has_method("update_terrain_mode"):
		speed_hud_view.update_terrain_mode(is_simple)
