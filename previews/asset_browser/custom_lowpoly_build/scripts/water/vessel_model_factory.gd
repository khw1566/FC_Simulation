extends RefCounted
class_name VesselModelFactory

## 원본 GLB 크기와 수면 기준점을 보존하는 공유 모델 캐시.
var _cache: Dictionary = {}
const Lighting = preload("res://scripts/core/asset_marker_lighting.gd")

func instantiate(entry: Dictionary) -> Node3D:
	var kind: String = entry.type
	if not _cache.has(kind):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(entry.glb_path, state)
		if error != OK:
			push_error("선박 모델 로드 실패: %s (%d)" % [entry.glb_path, error])
			return null
		var visual := document.generate_scene(state)
		if visual == null:
			return null
		var model := Node3D.new()
		model.name = kind
		visual.name = "Visual"
		model.add_child(visual)
		Lighting.vessel(model, float(entry.length_m), float(entry.beam_m), float(entry.get("deck_height_m", {"container_ship":5.0, "tugboat":2.2, "motor_boat":1.1, "lpg_carrier":4.0, "oil_tanker":5.5, "fishing_boat":1.5}.get(kind, 1.5))), kind)
		_assign_owner(visual, model)
		for child in model.get_children():
			_assign_owner(child, model)
		var packed := PackedScene.new()
		packed.pack(model)
		model.free()
		_cache[kind] = packed
	var instance: Node3D = _cache[kind].instantiate()
	instance.set_meta("vessel_type", kind)
	instance.set_meta("waterline_y_m", 0.0)
	instance.set_meta("forward_axis", "-Z")
	return instance

func _assign_owner(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_assign_owner(child, owner_node)
