extends Node
class_name DistrictHUDController

@export var district_service: Node
@export var hud_view: Control
@export var player_node: Node3D

func _ready() -> void:
	if district_service and hud_view:
		district_service.district_changed.connect(_on_district_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			if hud_view and hud_view.has_method("toggle_language"):
				hud_view.toggle_language()

func _physics_process(_delta: float) -> void:
	if district_service and player_node:
		district_service.update_player_position(player_node.global_position)

func _on_district_changed(district) -> void:
	if hud_view and hud_view.has_method("display_district"):
		hud_view.display_district(district)
