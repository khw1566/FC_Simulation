extends Node3D
class_name HorizonTerrainManager

const Sampler = preload("res://scripts/terrain/horizon_height_sampler.gd")
const Builder = preload("res://scripts/terrain/horizon_ring_builder.gd")
const CATALOG = "res://assets/generated/horizon/terrain.json"
@export var terrain_manager: Node3D
@export var auto_initialize: bool = true
var _map_id: String = ""
var _worker: Thread
var _instance: MeshInstance3D
var _material: ShaderMaterial

func _ready() -> void:
	if not auto_initialize:
		set_process(false)
		return
	var selection := get_node_or_null("/root/MapSelectionService")
	if selection and selection.selected_map:
		_map_id = selection.selected_map.id

func _process(_delta: float) -> void:
	if _instance:
		if terrain_manager and terrain_manager.terrain_material is ShaderMaterial:
			_material.set_shader_parameter("simple_contour_mode",terrain_manager.terrain_material.get_shader_parameter("simple_contour_mode"))
		return
	if _worker:
		if _worker.is_alive():
			return
		var result: Dictionary = _worker.wait_to_finish()
		_worker = null
		if not result.is_empty():
			_install(result.catalog,result.map_id,result.arrays)
		else:
			set_process(false)
		return
	if _map_id.is_empty():
		set_process(false)
		return
	if terrain_manager and not terrain_manager.load_complete:
		return
	# 메인 스레드에서는 상세 경계만 읽고 광역 표본·메쉬 배열 계산은 별도 스레드에서 수행한다.
	var edges := PackedFloat32Array()
	if terrain_manager:
		var half: float = terrain_manager.terrain_world_size*0.5-32.0
		for i in range(1024):
			var point := Builder.new().perimeter_point(i,256)*half
			edges.append(terrain_manager.get_terrain_elevation(point.x,point.y))
	_worker = Thread.new()
	_worker.start(_generate.bind(_map_id,edges))

func _generate(map_id: String,edges: PackedFloat32Array) -> Dictionary:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not catalog is Dictionary or not catalog.maps.has(map_id):
		return {}
	var sampler := Sampler.new()
	sampler.configure(catalog,map_id)
	var settings: Dictionary = catalog.settings.duplicate()
	settings["edge_heights"] = edges
	var arrays := Builder.new().build_arrays(sampler,settings)
	return {"catalog":catalog,"map_id":map_id,"arrays":arrays}

func _exit_tree() -> void:
	if _worker:
		_worker.wait_to_finish()

func _install(catalog: Dictionary,map_id: String,arrays: Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.name = "DistantTerrainRing"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/horizon_terrain.gdshader")
	var region: Dictionary = catalog.regional
	var image := Image.load_from_file(region.height_texture)
	if image:
		material.set_shader_parameter("regional_height_texture",ImageTexture.create_from_image(image))
	var map: Dictionary = catalog.maps[map_id]
	material.set_shader_parameter("flat_map",map.get("flat",false))
	material.set_shader_parameter("world_size_meters",float(map.world_size_meters))
	for item in [["map_bbox",map.bbox],["regional_bbox",region.bbox]]:
		var box: Dictionary = item[1]
		material.set_shader_parameter(item[0],Vector4(box.west,box.south,box.east,box.north))
	if terrain_manager and terrain_manager.terrain_material is ShaderMaterial:
		var source: ShaderMaterial = terrain_manager.terrain_material
		for parameter in ["splatmap_texture","has_splatmap","simple_contour_mode"]:
			material.set_shader_parameter(parameter,source.get_shader_parameter(parameter))
		for parameter in ["grass_color","rock_color","snow_color","dry_sand_color","wet_sand_color","coastal_cliff_color","forest_tone","farmland_tone","urban_tone","simple_land_color","simple_water_color"]:
			var color = source.get_shader_parameter(parameter)
			if color is Color:
				material.set_shader_parameter(parameter,Vector3(color.r,color.g,color.b))
	instance.material_override = material
	_instance = instance
	_material = material
	add_child(instance)
	return instance

func build(catalog: Dictionary, map_id: String, terrain: Node = null) -> MeshInstance3D:
	var sampler := Sampler.new()
	sampler.configure(catalog,map_id)
	return _install(catalog,map_id,Builder.new().build_arrays(sampler,catalog.settings,terrain))
