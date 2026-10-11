extends Node3D

var image: Image
var map_config

func configure(config) -> void:
	map_config = config
	image = Image.load_from_file(config.heightmap_path)

func get_terrain_elevation(x: float, z: float) -> float:
	return preload("res://scripts/terrain/coastline_water_carver.gd").sample_elevation_bilinear(image, x, z, map_config.world_size_meters, map_config.min_elevation, map_config.max_elevation)
