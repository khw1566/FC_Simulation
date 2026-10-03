extends Node3D
class_name KanmonWaterManager

@export var water_size: float = 32000.0 # 기본 32km 광역 해수면
@export var sea_level: float = 0.0
var watermask_path: String = ""
var map_world_size: float = 28000.0

func _ready() -> void:
	_init_from_map_selection()
	build_water_plane()

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

	add_child(mesh_instance)
	print("[KanmonWaterManager] Placed sea-level water plane (size %.0fm) at Y=%.1f" % [water_size, sea_level])
