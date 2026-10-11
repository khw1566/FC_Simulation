extends Node3D
class_name KanmonWaterManager

@export var water_size: float = 32000.0 # 기본 32km 광역 해수면
@export var sea_level: float = 0.0
var watermask_path: String = ""
var map_world_size: float = 28000.0
var _water_material: ShaderMaterial = null

func set_river_override(mask: Texture2D, rect: Vector4) -> void:
	if _water_material == null:
		return
	_water_material.set_shader_parameter("river_overlay_mask",mask)
	_water_material.set_shader_parameter("river_overlay_rect",rect)
	_water_material.set_shader_parameter("has_river_overlay",true)

func _ready() -> void:
	add_to_group("sea_water_plane")
	_init_from_map_selection()
	build_water_plane()

# 지형 관리자가 높이맵을 준비한 뒤 호출한다. 바다와 하천이 같은 수계 마스크·높이맵을 쓰게 하고,
# 해수면 아래 지형은 지형 셰이더에서 걷어내 바다 수면 평면만 보이게 한다(동일 평면 깜빡임 방지).
func set_water_source(height_texture: Texture2D, water_texture: Texture2D, min_height: float, max_height: float, terrain_material: ShaderMaterial, water_sdf: Texture2D = null) -> void:
	if _water_material == null or height_texture == null or water_texture == null:
		return
	_water_material.set_shader_parameter("water_mask_texture", water_texture)
	_water_material.set_shader_parameter("has_water_mask", true)
	_water_material.set_shader_parameter("terrain_height_texture", height_texture)
	_water_material.set_shader_parameter("terrain_min_height", min_height)
	_water_material.set_shader_parameter("terrain_max_height", max_height)
	_water_material.set_shader_parameter("sea_level_y", sea_level)
	_water_material.set_shader_parameter("has_terrain_height", true)
	if water_sdf != null:
		_water_material.set_shader_parameter("water_sdf_texture", water_sdf)
		_water_material.set_shader_parameter("has_water_sdf", true)
	if terrain_material != null:
		terrain_material.set_shader_parameter("sea_plane_level", sea_level)
		terrain_material.set_shader_parameter("has_sea_plane", true)

func _init_from_map_selection() -> void:
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			water_size = svc.selected_map.world_size_meters * 1.15
			sea_level = svc.selected_map.sea_level
			map_world_size = svc.selected_map.world_size_meters
			watermask_path = svc.selected_map.watermask_path
			if not svc.selected_map.sea_mask_path.is_empty():
				watermask_path = svc.selected_map.sea_mask_path

func build_water_plane() -> void:
	# sea_level이 -999.0 이하로 설정된 맵(수계/해수면 미구현 내륙 맵)은 수면 평면 생성을 건너뜀
	if sea_level <= -900.0:
		print("[KanmonWaterManager] Water plane disabled for current map (sea_level <= -900).")
		return

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(water_size, water_size)
	plane_mesh.subdivide_width = 32
	plane_mesh.subdivide_depth = 32

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = plane_mesh
	mesh_instance.name = "WaterPlaneInstance"
	mesh_instance.position.y = sea_level
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var water_shader = load("res://shaders/kanmon_water.gdshader")
	if water_shader:
		var mat := ShaderMaterial.new()
		mat.shader = water_shader
		mat.set_shader_parameter("world_size_meters", map_world_size)
		if not watermask_path.is_empty() and FileAccess.file_exists(watermask_path):
			var mask := preload("res://scripts/services/map_image_preloader.gd").read(watermask_path)
			if mask != null:
				mat.set_shader_parameter("water_mask_texture", ImageTexture.create_from_image(mask))
				mat.set_shader_parameter("has_water_mask", true)
		mesh_instance.material_override = mat
		_water_material = mat

	add_child(mesh_instance)
	print("[KanmonWaterManager] Placed sea-level water plane (size %.0fm) at Y=%.1f" % [water_size, sea_level])
