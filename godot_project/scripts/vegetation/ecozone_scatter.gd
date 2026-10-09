extends Node3D
class_name EcozoneScatter

## 태화강 둔치 생태 구역 식생 배치기. scatter_instances.json의 구역별 규칙 격자 인스턴스를
## 계열별 64m 청크 MultiMesh로 묶어 배치한다. 대상 지도가 아니면 아무 것도 하지 않는다.

const Batches = preload("res://scripts/vegetation/vegetation_batch_factory.gd")
const CATALOG := "res://assets/generated/taehwagang_ecozones/scatter_instances.json"
const NO_SHADOW_FAMILIES := ["silvergrass"]

@export var terrain_manager: Node3D
## 비우면 모든 구역. 예: ["bamboo", "silvergrass"]
@export var zones: PackedStringArray = PackedStringArray()
## 실행 시 지형 높이로 다시 맞춘다. 끄면 생성 시 기록한 y를 쓴다.
@export var resample_terrain := true
var load_complete := false
var placed_count := 0

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	if not FileAccess.file_exists(CATALOG):
		load_complete = true
		return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not catalog is Dictionary:
		push_warning("생태 구역 배치 파일을 읽지 못함")
		load_complete = true
		return
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or maps.selected_map.id != str(catalog.get("map_id", "")):
		load_complete = true
		return
	while is_instance_valid(terrain_manager) and not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var families: Dictionary = catalog.get("families", {})
	for layer in catalog.get("layers", []):
		if zones.size() > 0 and not zones.has(str(layer.zone)):
			continue
		if not families.has(layer.family):
			continue
		add_layer(layer, families[layer.family])
		await get_tree().process_frame
	load_complete = true

func add_layer(layer: Dictionary, family: Dictionary) -> void:
	var data: Array = layer.get("data", [])
	var transforms: Array[Transform3D] = []
	var use_terrain := resample_terrain and is_instance_valid(terrain_manager) and terrain_manager.has_method("get_terrain_elevation")
	for i in range(0, data.size() - 4, 5):
		var x := float(data[i])
		var z := float(data[i + 2])
		var y: float = terrain_manager.get_terrain_elevation(x, z) if use_terrain else float(data[i + 1])
		var basis := Basis(Vector3.UP, deg_to_rad(float(data[i + 3]))).scaled(Vector3.ONE * float(data[i + 4]))
		transforms.append(Transform3D(basis, Vector3(x, y, z)))
	if transforms.is_empty():
		return
	var node := Batches.build(str(family.scene_template), str(layer.kind), transforms, family.lod_ranges_m, not NO_SHADOW_FAMILIES.has(str(layer.family)))
	node.name = "%s_%s" % [layer.zone, layer.kind]
	add_child(node)
	placed_count += transforms.size()
