extends RefCounted
## 생태 구역 바닥 스플랫·텍스처를 지형 셰이더 머티리얼(procedural_terrain)에 연결한다.
## 잔디는 개체 없이 이 바닥 텍스처로만, 억새·갈대는 원경에서 이 텍스처로 표현된다.

const TEXTURE_UNIFORMS := {
	"lawn": "ecozone_lawn",
	"silvergrass_ground": "ecozone_silvergrass",
	"bamboo_litter": "ecozone_bamboo_litter",
	"reed_mud": "ecozone_reed_mud",
	"woodland_soil": "ecozone_woodland_soil",
	"meadow": "ecozone_meadow",
}

## scale, offset: 원천 월드 xz → 현재 지도 월드 xz 변환 계수(target = source * scale + offset).
static func bind(material: Material, ground: Dictionary, scale: Vector2, offset: Vector2) -> bool:
	if not material is ShaderMaterial:
		return false
	var shader_material := material as ShaderMaterial
	var source_size := float(ground.get("source_world_size_m", 8000.0))
	var splat_a := _texture(str(ground.get("splat_a", "")), false)
	var splat_b := _texture(str(ground.get("splat_b", "")), false)
	if splat_a == null or splat_b == null:
		return false
	# 스플랫 UV = source / size + 0.5 = ((target - offset) / scale) / size + 0.5
	var uv_scale := Vector2(1.0 / (scale.x * source_size), 1.0 / (scale.y * source_size))
	shader_material.set_shader_parameter("ecozone_uv_scale", uv_scale)
	shader_material.set_shader_parameter("ecozone_uv_offset", Vector2(0.5, 0.5) - offset * uv_scale)
	shader_material.set_shader_parameter("ecozone_splat_a", splat_a)
	shader_material.set_shader_parameter("ecozone_splat_b", splat_b)
	var textures: Dictionary = ground.get("textures", {})
	for key in TEXTURE_UNIFORMS:
		var texture := _texture(str(textures.get(key, "")), true)
		if texture != null:
			shader_material.set_shader_parameter(TEXTURE_UNIFORMS[key], texture)
	shader_material.set_shader_parameter("ecozone_tile_m", float(ground.get("tile_m", 6.0)))
	shader_material.set_shader_parameter("ecozone_fade_distance_m", float(ground.get("fade_distance_m", 6000.0)))
	shader_material.set_shader_parameter("has_ecozone", true)
	return true

static func _texture(path: String, mipmaps: bool) -> ImageTexture:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	if mipmaps:
		image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
