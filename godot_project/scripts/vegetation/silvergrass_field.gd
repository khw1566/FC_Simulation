extends Node3D
## 카메라 주변 억새 GPU 필드. 근경 다발 링(0~radius)과 원경 카드 링(radius~card_radius) 두 MultiMesh를
## 카메라 위치(각 간격 단위로 맞춤)로 옮긴다. 셰이더가 생태 구역 스플랫으로 억새·갈대 칸만 세우고,
## 범위 밖·게임 수면·해수면 아래는 비우며, 렌더된 지형 높이에 밑동을 붙인다.

const Tuft = preload("res://scripts/vegetation/silvergrass_tuft.gd")
const SHADER := "res://shaders/silvergrass_field.gdshader"

var _rings: Array = []
var _terrain: Node3D
var _height_bound := false

## settings: ground_blend.json의 silvergrass_field. terrain_material: 생태 구역 바닥이 연결된 지형 재질.
func setup(settings: Dictionary, terrain_material: ShaderMaterial, card_texture: Texture2D, terrain_manager: Node3D) -> void:
	_terrain = terrain_manager
	var near_radius := float(settings.get("radius_m", 120.0))
	var shared := {
		"eco_splat": terrain_material.get_shader_parameter("ecozone_splat_a"),
		"eco_uv_scale": terrain_material.get_shader_parameter("ecozone_uv_scale"),
		"eco_uv_offset": terrain_material.get_shader_parameter("ecozone_uv_offset"),
		"thin_start": float(settings.get("thin_start_m", 50.0)),
		"density": float(settings.get("density", 1.0)),
		"wave_length": float(settings.get("wave_length_m", 22.0)),
		"wave_speed": float(settings.get("wave_speed_mps", 7.0)),
		"sway_strength": float(settings.get("sway_strength_m", 0.45)),
	}
	var water = terrain_material.get_shader_parameter("water_mask_texture")
	if water is Texture2D:
		shared["game_water"] = water
		shared["has_game_water"] = true
		shared["water_world_size"] = float(terrain_material.get_shader_parameter("world_size_meters"))
	_add_ring("SilvergrassNear", Tuft.build(), float(settings.get("spacing_m", 0.9)), 0.0, near_radius, false, null, shared)
	if card_texture != null:
		var far_radius := float(settings.get("card_radius_m", 450.0))
		_add_ring("SilvergrassCards", Tuft.build_card(), float(settings.get("card_spacing_m", 4.0)), near_radius - 15.0, far_radius, true, card_texture, shared)

func _add_ring(node_name: String, mesh: Mesh, spacing: float, inner: float, outer: float, cards: bool, card_texture: Texture2D, shared: Dictionary) -> void:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	for key in shared:
		material.set_shader_parameter(key, shared[key])
	material.set_shader_parameter("spacing", spacing)
	material.set_shader_parameter("inner_radius", inner)
	material.set_shader_parameter("radius", outer)
	material.set_shader_parameter("card_mode", cards)
	if cards:
		material.set_shader_parameter("card_texture", card_texture)
		material.set_shader_parameter("thin_start", outer)
		material.set_shader_parameter("sway_strength", float(shared["sway_strength"]) * 0.7)
	_bind_terrain_height(material)
	var count := int(ceil(outer * 2.0 / spacing))
	var half := (count - 1) * 0.5
	var transforms: Array[Transform3D] = []
	for z in range(count):
		for x in range(count):
			var offset := Vector3((x - half) * spacing, 0.0, (z - half) * spacing)
			# 원경 링은 안쪽 원 안의 칸을 만들지 않아 정점 처리량을 줄인다.
			if inner <= 0.0 or Vector2(offset.x, offset.z).length() >= inner - spacing * 2.0:
				transforms.append(Transform3D(Basis.IDENTITY, offset))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var low := _terrain_number("min_elevation", -50.0)
	var high := _terrain_number("max_elevation", 500.0)
	node.custom_aabb = AABB(Vector3(-outer - 5.0, low - 5.0, -outer - 5.0), Vector3(outer * 2.0 + 10.0, high - low + 10.0, outer * 2.0 + 10.0))
	add_child(node)
	_rings.append([node, spacing, material])

## 렌더된 지형과 같은 높이(청크 LOD 반영)를 쓰기 위해 도로 재질의 지형 높이 균일 변수를 복사한다.
func _bind_terrain_height(material: ShaderMaterial) -> void:
	if not is_instance_valid(_terrain) or not _terrain.has_method("create_road_material"):
		return
	var road = _terrain.create_road_material()
	if not road is ShaderMaterial:
		return
	var pairs := {"road_heightmap": "th_heightmap", "terrain_lods": "th_terrain_lods", "chunk_counts": "th_chunk_counts",
		"world_size": "th_world_size", "terrain_base_resolution": "th_base_resolution", "min_elevation": "th_min_elevation", "max_elevation": "th_max_elevation"}
	for key in pairs:
		material.set_shader_parameter(pairs[key], road.get_shader_parameter(key))
	material.set_shader_parameter("th_enabled", true)
	_height_bound = true

func _terrain_number(property: String, fallback: float) -> float:
	var value = _terrain.get(property) if is_instance_valid(_terrain) else null
	return float(value) if value != null else fallback

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := camera.global_position
	var fallback := 0.0
	if not _height_bound and is_instance_valid(_terrain) and _terrain.has_method("get_terrain_elevation"):
		fallback = _terrain.get_terrain_elevation(p.x, p.z)
	for ring in _rings:
		var spacing: float = ring[1]
		(ring[0] as Node3D).global_position = Vector3(round(p.x / spacing) * spacing, 0.0, round(p.z / spacing) * spacing)
		if not _height_bound:
			(ring[2] as ShaderMaterial).set_shader_parameter("th_fallback_height", fallback)
