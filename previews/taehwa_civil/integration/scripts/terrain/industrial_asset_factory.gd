extends RefCounted
class_name IndustrialAssetFactory

## 원본 임포트 캐시를 갱신하지 않는 GLB 공유 모델과 조명·연기 조립.
## GLB 해석과 충돌 형상 생성은 작업 스레드에서 수행하고, 준비된 모델만 메인 스레드에서 배치한다.
const SceneCache = preload("res://scripts/core/threaded_scene_cache.gd")
var _models := SceneCache.new()
var _effects: Dictionary = {}

## 설비와 부착물 모델이 모두 준비됐으면 true. 아직이면 작업 스레드 읽기를 시작하고 false를 돌려준다.
func prepare(entry: Dictionary) -> bool:
	var ready := _models.request(str(entry.glb_path), _build_scene.bind(str(entry.glb_path)))
	for spec in entry.get("attachments",[]):
		ready = _models.request(str(spec.glb_path), _build_scene.bind(str(spec.glb_path))) and ready
	return ready

func dispose() -> void:
	_models.dispose()

func instantiate(entry: Dictionary) -> Node3D:
	if not prepare(entry):
		return null
	var model := _models.instantiate(str(entry.glb_path)) as Node3D
	if model == null:
		return null
	model.name = str(entry.id)
	_attach_lighting(model,entry.get("night_lighting",{}))
	for spec in entry.get("attachments",[]):
		var attachment := _models.instantiate(str(spec.glb_path)) as Node3D
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

## 작업 스레드에서 실행한다. 장면 트리에 붙지 않은 노드만 다룬다.
static func _build_scene(path: String) -> PackedScene:
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
	return packed

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

static func _owners(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_owners(child,owner_node)

static func _collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision()
	for child in node.get_children():
		_collisions(child)
