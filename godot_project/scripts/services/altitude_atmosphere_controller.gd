extends Node
class_name AltitudeAtmosphereController

@export var player_camera: Camera3D
@export var world_environment: WorldEnvironment
const Density = preload("res://scripts/models/atmosphere_scattering_model.gd")
var _sky: ShaderMaterial
var _last_altitude: float = -1000000.0
var _near: float = 0.05

func _ready() -> void:
	if world_environment and world_environment.environment:
		var environment := world_environment.environment
		# 해수면 안개가 성층권 하늘까지 회색으로 덮는 것을 방지한다.
		environment.fog_sky_affect = 0.0
		if environment.sky:
			_sky = environment.sky.sky_material as ShaderMaterial
	if player_camera:
		_near = player_camera.near
	_process(0.0)

func _process(_delta: float) -> void:
	if not player_camera or not _sky:
		return
	var altitude := maxf(player_camera.global_position.y, 0.0)
	if absf(altitude - _last_altitude) < 2.0:
		return
	_last_altitude = altitude
	_sky.set_shader_parameter("observer_altitude_m", altitude)
	_sky.set_shader_parameter("air_density_ratio", Density.density(altitude))
	var horizon_distance := sqrt(2.0*6371000.0*altitude+altitude*altitude)
	player_camera.far = clampf(horizon_distance*1.6,450000.0,1600000.0)
	player_camera.near = maxf(_near, minf(altitude / 30000.0, 2.0))
