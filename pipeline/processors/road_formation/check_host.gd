extends Node3D
var max_view_distance := 5000.0
var road_material: Material = StandardMaterial3D.new()
var walking_path_material := StandardMaterial3D.new()
var unpaved_road_material := StandardMaterial3D.new()
var tunnel_wall_material := StandardMaterial3D.new()
var bridge_truss_material := StandardMaterial3D.new()
func _configure_road_bounds(instance: MeshInstance3D) -> void:
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
