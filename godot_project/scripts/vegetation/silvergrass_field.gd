extends Node3D
## 카메라 주변 반경 안에만 억새를 세우는 GPU 필드. 격자 MultiMesh 하나를 카메라 위치(격자 간격 단위로 맞춤)로
## 옮기고, 셰이더가 생태 구역 스플랫으로 억새·갈대 칸만 세우며 렌더된 지형 높이에 밑동을 붙인다.
## 반경 밖은 지형 바닥의 황금빛 억새 텍스처가 맡는다.

const Tuft = preload("res://scripts/vegetation/silvergrass_tuft.gd")
const SHADER := "res://shaders/silvergrass_field.gdshader"

var spacing := 1.1
var radius := 130.0
var _multi: MultiMeshInstance3D
var _material: ShaderMaterial
var _terrain: Node3D
var _height_bound := false

## settings: ground_blend.json의 silvergrass_field. splat: 억새(G)·갈대(A) 스플랫. uv_scale/offset: 현재 지도 월드 → 스플랫 UV.
func setup(settings: Dictionary, splat: Texture2D, uv_scale: Vector2, uv_offset: Vector2, terrain_manager: Node3D) -> void:
	spacing = float(settings.get("spacing_m", 1.1))
	radius = float(settings.get("radius_m", 130.0))
	_terrain = terrain_manager
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER)
	_material.set_shader_parameter("eco_splat", splat)
	_material.set_shader_parameter("eco_uv_scale", uv_scale)
	_material.set_shader_parameter("eco_uv_offset", uv_offset)
	_material.set_shader_parameter("spacing", spacing)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("thin_start", float(settings.get("thin_start_m", 55.0)))
	_material.set_shader_parameter("density", float(settings.get("density", 1.0)))
	_material.set_shader_parameter("wave_length", float(settings.get("wave_length_m", 22.0)))
	_material.set_shader_parameter("wave_speed", float(settings.get("wave_speed_mps", 7.0)))
	_material.set_shader_parameter("sway_strength", float(settings.get("sway_strength_m", 0.45)))
	_bind_terrain_height()
	var count := int(ceil(radius * 2.0 / spacing))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = Tuft.build()
	multi.instance_count = count * count
	var half := (count - 1) * 0.5
	for z in range(count):
		for x in range(count):
			multi.set_instance_transform(z * count + x, Transform3D(Basis.IDENTITY, Vector3((x - half) * spacing, 0.0, (z - half) * spacing)))
	_multi = MultiMeshInstance3D.new()
	_multi.name = "SilvergrassField"
	_multi.multimesh = multi
	_multi.material_override = _material
	_multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 셰이더가 정점을 지형 높이로 옮기므로 높이 범위 전체를 덮는 경계 상자를 준다.
	var low := _terrain_number("min_elevation", -50.0)
	var high := _terrain_number("max_elevation", 500.0)
	_multi.custom_aabb = AABB(Vector3(-radius - 5.0, low - 5.0, -radius - 5.0), Vector3(radius * 2.0 + 10.0, high - low + 10.0, radius * 2.0 + 10.0))
	add_child(_multi)

## 렌더된 지형과 같은 높이(청크 LOD 반영)를 쓰기 위해 도로 재질의 지형 높이 균일 변수를 복사한다.
func _bind_terrain_height() -> void:
	if not is_instance_valid(_terrain) or not _terrain.has_method("create_road_material"):
		return
	var road = _terrain.create_road_material()
	if not road is ShaderMaterial:
		return
	var pairs := {"road_heightmap": "th_heightmap", "terrain_lods": "th_terrain_lods", "chunk_counts": "th_chunk_counts",
		"world_size": "th_world_size", "terrain_base_resolution": "th_base_resolution", "min_elevation": "th_min_elevation", "max_elevation": "th_max_elevation"}
	for key in pairs:
		_material.set_shader_parameter(pairs[key], road.get_shader_parameter(key))
	_material.set_shader_parameter("th_enabled", true)
	_height_bound = true

func _terrain_number(property: String, fallback: float) -> float:
	var value = _terrain.get(property) if is_instance_valid(_terrain) else null
	return float(value) if value != null else fallback

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _multi == null:
		return
	var p := camera.global_position
	_multi.global_position = Vector3(round(p.x / spacing) * spacing, 0.0, round(p.z / spacing) * spacing)
	if not _height_bound and is_instance_valid(_terrain) and _terrain.has_method("get_terrain_elevation"):
		_material.set_shader_parameter("th_fallback_height", _terrain.get_terrain_elevation(p.x, p.z))
