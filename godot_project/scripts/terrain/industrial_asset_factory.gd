extends RefCounted
class_name IndustrialAssetFactory

## 원본 임포트 캐시를 갱신하지 않는 GLB 공유 모델과 조명·연기 조립.
var _models: Dictionary = {}
var _effects: Dictionary = {}

func instantiate(entry: Dictionary) -> Node3D:
	var model := _visual(str(entry.glb_path))
	if model == null:
		return null
	model.name = str(entry.id)
	_attach_lighting(model,entry.get("night_lighting",{}))
	for spec in entry.get("attachments",[]):
		var attachment := _visual(str(spec.glb_path))
		if attachment:
			var p: Array = spec.position_m
			attachment.position = Vector3(p[0],p[1],p[2])
			model.add_child(attachment)
			_attach_lighting(attachment,spec.get("night_lighting",{}))
	for outlet in entry.get("smoke_outlets_m",[]):
		var path := "res://assets/generated/industrial_plant/smoke_gray.tscn"
		if not _effects.has(path):
			_effects[path] = load(path)
		var plume: Node3D = _effects[path].instantiate()
		plume.position = Vector3(outlet[0],outlet[1],outlet[2])
		if plume is GeometryInstance3D:
			plume.visibility_range_end = 1200.0
		model.add_child(plume)
	return model

func _visual(path: String) -> Node3D:
	if not _models.has(path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path,state)!=OK:
			push_error("공단 모델 로드 실패: "+path)
			return null
		var visual := document.generate_scene(state)
		if visual == null:
			return null
		var model := Node3D.new()
		model.add_child(visual)
		_collisions(visual)
		_owners(visual,model)
		var packed := PackedScene.new()
		packed.pack(model)
		model.free()
		_models[path] = packed
	return _models[path].instantiate()

func _attach_lighting(parent: Node3D, spec: Dictionary) -> void:
	var path: String = spec.get("scene_path","")
	if path.is_empty():
		return
	if not _effects.has(path):
		_effects[path] = load(path)
	if _effects[path]:
		var lighting: Node3D = _effects[path].instantiate()
		lighting.name = "NightLighting"
		lighting.set("local_lights_enabled",false)
		parent.add_child(lighting)

func _owners(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_owners(child,owner_node)

func _collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision()
	for child in node.get_children():
		_collisions(child)
