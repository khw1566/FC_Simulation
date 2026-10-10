extends Node3D
class_name EcozoneScatter

## 태화강 둔치 생태 구역 표현기. 원천 좌표를 위경도로 바꿔 현재 지도(울산 80km, 둔치 정밀 지도 등)에 맞춘다.
## - 근경 개체: scatter_instances.json을 계열별 64m 청크 MultiMesh로 묶는다(억새·갈대·대나무는 흔들림 셰이더).
## - 숲 덩어리: forest_masses.json으로 대숲·활엽수림 연속 수관 메시를 만든다.
## - 바닥: ground_blend.json의 스플랫·텍스처를 지형 셰이더에 연결한다(잔디, 억새·갈대 원경).

const Batches = preload("res://scripts/vegetation/vegetation_batch_factory.gd")
const Masses = preload("res://scripts/vegetation/forest_mass_builder.gd")
const Ground = preload("res://scripts/vegetation/ecozone_ground_binder.gd")
const Field = preload("res://scripts/vegetation/silvergrass_field.gd")
const CATALOG := "res://assets/generated/taehwagang_ecozones/scatter_instances.json"
const MASSES := "res://assets/generated/taehwagang_ecozones/forest_masses.json"
const GROUND := "res://assets/generated/taehwagang_ecozones/ground_blend.json"
const SWAY_SHADER := "res://shaders/vegetation_sway.gdshader"
const NO_SHADOW_FAMILIES := ["silvergrass"]

@export var terrain_manager: Node3D
## 비우면 모든 구역. 예: ["bamboo", "silvergrass"]
@export var zones: PackedStringArray = PackedStringArray()
## 실행 시 지형 높이로 다시 맞춘다. 끄면 생성 시 기록한 y를 쓴다(원천 지도에서만 의미 있음).
@export var resample_terrain := true
var load_complete := false
var placed_count := 0
var mass_count := 0
var ground_bound := false
var field_ready := false
## 원천 월드 좌표 → 현재 지도 월드 좌표: target = source * _scale + _offset
var _scale := Vector2.ONE
var _offset := Vector2.ZERO
var _half_extent := INF
var _water_image: Image
var _water_checked := false
var _map_size := 1.0

func _ready() -> void:
	_initialize.call_deferred()

func _initialize() -> void:
	var maps := get_node_or_null("/root/MapSelectionService")
	if maps == null or maps.selected_map == null or not FileAccess.file_exists(CATALOG):
		load_complete = true
		return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if not catalog is Dictionary or not configure_mapping(catalog, maps.selected_map):
		load_complete = true
		return
	while is_instance_valid(terrain_manager) and not terrain_manager.load_complete:
		if not terrain_manager.load_error.is_empty():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
	bind_ground()
	add_forest_masses()
	await get_tree().process_frame
	var families: Dictionary = catalog.get("families", {})
	for layer in catalog.get("layers", []):
		if zones.size() > 0 and not zones.has(str(layer.zone)):
			continue
		if not families.has(layer.family):
			continue
		add_layer(layer, families[layer.family])
		await get_tree().process_frame
	print("EcozoneScatter: ", placed_count, " placed, ", mass_count, " canopy chunks, ground ", ground_bound)
	load_complete = true

func bind_ground() -> void:
	if not FileAccess.file_exists(GROUND) or not is_instance_valid(terrain_manager):
		return
	var ground = JSON.parse_string(FileAccess.get_file_as_string(GROUND))
	var material = terrain_manager.get("terrain_material")
	if ground is Dictionary and material is Material:
		ground_bound = Ground.bind(material, ground, _scale, _offset)
	if ground is Dictionary and ground.get("silvergrass_field") is Dictionary and ground_bound:
		add_silvergrass_field(ground, material)

## 억새·갈대 GPU 필드(근경 다발 + 원경 카드). 바닥 혼합과 같은 스플랫·UV 변환을 쓴다.
func add_silvergrass_field(ground: Dictionary, material: ShaderMaterial) -> void:
	if not material.get_shader_parameter("ecozone_splat_a") is Texture2D:
		return
	var card: Texture2D = null
	var card_path := str(ground.get("textures", {}).get("silvergrass_card", ""))
	if not card_path.is_empty() and FileAccess.file_exists(card_path):
		var image := Image.load_from_file(card_path)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			card = ImageTexture.create_from_image(image)
	var field := Field.new()
	field.name = "SilvergrassField"
	add_child(field)
	field.setup(ground.silvergrass_field, material, card, terrain_manager)
	field_ready = true

func add_forest_masses() -> void:
	if not FileAccess.file_exists(MASSES):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(MASSES))
	if not data is Dictionary:
		return
	for mass in data.get("masses", []):
		if zones.size() > 0 and not zones.has(str(mass.zone)):
			continue
		var node := Masses.build(mass, int(data.label_size), float(data.source_world_size_m), to_target, height_at)
		add_child(node)
		mass_count += node.get_child_count()

func to_target(source_xz: Vector2) -> Vector2:
	return source_xz * _scale + _offset

func height_at(x: float, z: float) -> float:
	if is_instance_valid(terrain_manager) and terrain_manager.has_method("get_terrain_elevation"):
		return terrain_manager.get_terrain_elevation(x, z)
	return 0.0

## 근경 식생 셰이더 머티리얼: 흔들림(sway)과 숲 덩어리로 넘기는 원거리 디더 전환(fade_far_m).
func sway_material(family: Dictionary) -> ShaderMaterial:
	if not ResourceLoader.exists(SWAY_SHADER) or not (family.has("sway") or family.has("fade_far_m")):
		return null
	var material := ShaderMaterial.new()
	material.shader = load(SWAY_SHADER)
	var sway: Dictionary = family.get("sway", {})
	material.set_shader_parameter("sway_height_m", float(sway.get("height_m", 2.4)))
	material.set_shader_parameter("sway_strength_m", float(sway.get("strength_m", 0.0)))
	material.set_shader_parameter("sway_speed", float(sway.get("speed", 1.0)))
	material.set_shader_parameter("use_vertex_weight", bool(sway.get("vertex_weight", false)))
	material.set_shader_parameter("fade_far_m", float(family.get("fade_far_m", 0.0)))
	material.set_shader_parameter("fade_band_m", float(family.get("fade_band_m", 20.0)))
	return material

## 원천 bbox와 현재 지도 bbox가 겹치면 선형 변환을 설정한다. 겹치지 않으면 false.
func configure_mapping(catalog: Dictionary, map) -> bool:
	var source: Dictionary = catalog.get("source_bbox", {})
	if source.is_empty():
		return str(catalog.get("map_id", "")) == str(map.id)
	if source.east < map.bbox_west or source.west > map.bbox_east or source.north < map.bbox_south or source.south > map.bbox_north:
		return false
	var source_size := float(catalog.get("source_world_size_m", 8000.0))
	var size: float = map.world_size_meters
	var kx: float = (source.east - source.west) / (map.bbox_east - map.bbox_west) * size / source_size
	var kz: float = (source.north - source.south) / (map.bbox_north - map.bbox_south) * size / source_size
	var center_lon: float = (source.west + source.east) * 0.5
	var center_lat: float = (source.south + source.north) * 0.5
	_scale = Vector2(kx, kz)
	_offset = Vector2(((center_lon - map.bbox_west) / (map.bbox_east - map.bbox_west) - 0.5) * size,
		((map.bbox_north - center_lat) / (map.bbox_north - map.bbox_south) - 0.5) * size)
	_half_extent = size * 0.5
	_map_size = size
	return true

## 실행 중 지형이 쓰는 수면 마스크로 마지막 검사를 한다(생성 단계 제외 마스크의 안전망).
func is_water(x: float, z: float) -> bool:
	if not _water_checked:
		_water_checked = true
		var water = terrain_manager.get("_full_watermask_image") if is_instance_valid(terrain_manager) else null
		_water_image = water if water is Image and not water.is_empty() else null
	if _water_image == null:
		return false
	var size := float(_water_image.get_width())
	var u := clampi(roundi((x / _map_size + 0.5) * (size - 1.0)), 0, _water_image.get_width() - 1)
	var v := clampi(roundi((z / _map_size + 0.5) * (float(_water_image.get_height()) - 1.0)), 0, _water_image.get_height() - 1)
	return _water_image.get_pixel(u, v).r > 0.4

func add_layer(layer: Dictionary, family: Dictionary) -> void:
	var data: Array = layer.get("data", [])
	var transforms: Array[Transform3D] = []
	var use_terrain := resample_terrain and is_instance_valid(terrain_manager) and terrain_manager.has_method("get_terrain_elevation")
	for i in range(0, data.size() - 4, 5):
		var x := float(data[i]) * _scale.x + _offset.x
		var z := float(data[i + 2]) * _scale.y + _offset.y
		if absf(x) > _half_extent or absf(z) > _half_extent or is_water(x, z):
			continue
		var y: float = terrain_manager.get_terrain_elevation(x, z) if use_terrain else float(data[i + 1])
		var basis := Basis(Vector3.UP, deg_to_rad(float(data[i + 3]))).scaled(Vector3.ONE * float(data[i + 4]))
		transforms.append(Transform3D(basis, Vector3(x, y, z)))
	if transforms.is_empty():
		return
	var node := Batches.build(str(family.scene_template), str(layer.kind), transforms, family.lod_ranges_m, not NO_SHADOW_FAMILIES.has(str(layer.family)), 64.0, sway_material(family))
	node.name = "%s_%s" % [layer.zone, layer.kind]
	add_child(node)
	placed_count += transforms.size()
