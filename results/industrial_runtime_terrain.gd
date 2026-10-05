extends Node3D

const Samples = preload("res://scripts/terrain/coastline_water_carver.gd")
var terrain_world_size := 80000.0
var grid_chunks_x := 11
var grid_chunks_y := 11
var load_complete := true
var load_error := ""
var _image: Image

func _init() -> void:
	_image = Image.load_from_file("res://assets/maps/ulsan_metro_80km/hydro/coastal_heightmap_16bit.png")
	_image.convert(Image.FORMAT_RF)

func get_terrain_elevation(x: float,z: float) -> float:
	return Samples.sample_elevation_bilinear(_image,x,z,terrain_world_size,-30,1300)

func get_rendered_terrain_elevation(x: float,z: float) -> float:
	return get_terrain_elevation(x,z)

func create_road_material() -> Material:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20,0.20,0.20)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
