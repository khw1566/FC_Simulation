extends "res://check_host.gd"
var _batch_serial := 0
var chunk_size := 1500.0
var building_material: Material = StandardMaterial3D.new()
var _building_chunk_nodes: Dictionary = {}
var _last_cull_check_pos := Vector3.ZERO
var player_node: Node3D
var _high_cull_altitude := 600.0
func _sample_ground_height(_x: float,_z: float,_fallback: float = 0.0) -> float:
	return 0.0
func _apply_chunk_visibility(info: Dictionary,_point: Vector2,_high: bool) -> void:
	info.node.visible = true
