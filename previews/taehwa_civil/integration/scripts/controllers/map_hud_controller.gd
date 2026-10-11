extends Node
class_name MapHUDController

const AtmosphereStateModelClass = preload("res://scripts/models/atmosphere_state_model.gd")
const SurfaceClimateModelClass = preload("res://scripts/models/surface_climate_model.gd")

@export var map_hud_view: Control
@export var player_node: Node3D
@export var weather_manager: Node3D

func _ready() -> void:
	if map_hud_view != null:
		map_hud_view.travel_requested.connect(_travel_to_map_point)
		map_hud_view.map_visibility_changed.connect(func(open):
			if player_node != null:
				player_node.set("map_navigation_active", open)
		)

func _travel_to_map_point(point: Vector2) -> void:
	if player_node == null:
		return
	var terrain := get_parent().get_node_or_null("TerrainManager")
	if terrain == null or not terrain.has_method("get_terrain_elevation"):
		return
	var ground: float = terrain.call("get_terrain_elevation", point.x, point.y)
	var height: float = maxf(player_node.global_position.y, maxf(ground, 0.0) + 100.0)
	player_node.global_position = Vector3(point.x, height, point.y)
	if player_node.has_method("reset_map_travel_motion"):
		player_node.call("reset_map_travel_motion")
	terrain.call("_update_chunks_lod")
	map_hud_view.update_player_transform(player_node.global_position, player_node.rotation.y)
	map_hud_view.recenter_on_player()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			if map_hud_view and map_hud_view.has_method("toggle_fullscreen_map"):
				map_hud_view.toggle_fullscreen_map()

func _physics_process(_delta: float) -> void:
	if map_hud_view and player_node:
		var pos := player_node.global_position
		var yaw := player_node.rotation.y
		var fov := 70.0
		if player_node.has_node("Camera3D"):
			var cam: Camera3D = player_node.get_node("Camera3D")
			if cam:
				fov = cam.fov
		if map_hud_view.has_method("update_player_transform"):
			map_hud_view.update_player_transform(pos, yaw, fov)

		# 미니맵 하단 상시 TAS / IAS 및 마하수 갱신
		if map_hud_view.has_method("update_airspeed_display"):
			var speed_ms := 0.0
			if "velocity" in player_node:
				speed_ms = player_node.velocity.length()

			var w_type := 2
			if weather_manager:
				w_type = int(weather_manager.get("current_weather"))

			var atmo = AtmosphereStateModelClass.calculate_at_altitude(pos.y, speed_ms, w_type, SurfaceClimateModelClass.resolve_hour(weather_manager))
			map_hud_view.call("update_airspeed_display", atmo.true_airspeed_kmh, atmo.indicated_airspeed_kmh, atmo.mach_number)
