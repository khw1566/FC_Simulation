// 태화강 둔치 생태 구역 바닥 혼합 함수. 지형 셰이더에서 #include 후 albedo에 섞어 쓴다.
// 스플랫 A(R 잔디, G 억새, B 대숲 낙엽, A 수변 갈대), 스플랫 B(R 수림, G 들풀, A 둔치 평탄면).
// 스플랫 UV = 현재 지도 월드 xz * ecozone_uv_scale + ecozone_uv_offset (EcozoneGroundBinder가 설정).

uniform bool has_ecozone = false;
uniform vec2 ecozone_uv_scale = vec2(0.000125);
uniform vec2 ecozone_uv_offset = vec2(0.5);
uniform sampler2D ecozone_splat_a : filter_linear, repeat_disable;
uniform sampler2D ecozone_splat_b : filter_linear, repeat_disable;
uniform sampler2D ecozone_lawn : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_silvergrass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_bamboo_litter : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_reed_mud : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_woodland_soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_meadow : source_color, filter_linear_mipmap, repeat_enable;
// 원경 숲 바닥색: 대숲·수림 구역은 멀리서 낙엽 바닥 대신 수관 평균색으로 칠해 숲으로 읽히게 한다.
uniform sampler2D ecozone_canopy_bamboo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_canopy_broadleaf : source_color, filter_linear_mipmap, repeat_enable;
uniform bool ecozone_has_canopy = false;
uniform float ecozone_tile_m = 6.0;
uniform float ecozone_fade_distance_m = 6000.0;
// 원경 단색: ecozone_flat_near_m~far_m 구간에서 텍스처 무늬가 사라지고, 가장 작은 밉맵(=텍스처 평균색)에
// 수백 m 규모의 완만한 그라데이션만 남는다. 밉맵 표본이라 렌더러 색공간과 무관하게 근경 텍스처와 같은 밝기다.
uniform float ecozone_flat_near_m = 150.0;
uniform float ecozone_flat_far_m = 450.0;
uniform float ecozone_gradient_strength = 0.08;

vec3 ecozone_blend(vec3 base_albedo, vec2 world_xz, float view_distance) {
	if (!has_ecozone) {
		return base_albedo;
	}
	vec2 map_uv = world_xz * ecozone_uv_scale + ecozone_uv_offset;
	if (map_uv.x < 0.0 || map_uv.y < 0.0 || map_uv.x > 1.0 || map_uv.y > 1.0) {
		return base_albedo;
	}
	vec4 a = texture(ecozone_splat_a, map_uv);
	vec4 b = texture(ecozone_splat_b, map_uv);
	float weight = a.r + a.g + a.b + a.a + b.r + b.g;
	if (weight < 0.001) {
		return base_albedo;
	}
	float flat_mix = smoothstep(ecozone_flat_near_m, ecozone_flat_far_m, view_distance);
	vec2 c = vec2(0.5);
	vec3 bamboo_far = ecozone_has_canopy ? textureLod(ecozone_canopy_bamboo, c, 12.0).rgb : textureLod(ecozone_bamboo_litter, c, 12.0).rgb;
	vec3 woodland_far = ecozone_has_canopy ? textureLod(ecozone_canopy_broadleaf, c, 12.0).rgb : textureLod(ecozone_woodland_soil, c, 12.0).rgb;
	vec3 flat_color = (textureLod(ecozone_lawn, c, 12.0).rgb * a.r + textureLod(ecozone_silvergrass, c, 12.0).rgb * a.g
		+ bamboo_far * a.b + textureLod(ecozone_reed_mud, c, 12.0).rgb * a.a
		+ woodland_far * b.r + textureLod(ecozone_meadow, c, 12.0).rgb * b.g) / weight;
	// 수백 m 규모의 완만한 밝기 그라데이션(반복 무늬 없음)
	float gradient = sin(world_xz.x * 0.0047 + 1.3) * sin(world_xz.y * 0.0039 - 0.7) * 0.6 + sin((world_xz.x + world_xz.y) * 0.0017) * 0.4;
	flat_color *= 1.0 + gradient * ecozone_gradient_strength;
	vec3 mixed = flat_color;
	if (flat_mix < 0.999) {
		vec2 tile_uv = world_xz / ecozone_tile_m;
		vec3 detail = (texture(ecozone_lawn, tile_uv).rgb * a.r + texture(ecozone_silvergrass, tile_uv).rgb * a.g
			+ texture(ecozone_bamboo_litter, tile_uv).rgb * a.b + texture(ecozone_reed_mud, tile_uv).rgb * a.a
			+ texture(ecozone_woodland_soil, tile_uv).rgb * b.r + texture(ecozone_meadow, tile_uv).rgb * b.g) / weight;
		mixed = mix(detail, flat_color, flat_mix);
	}
	float fade = 1.0 - smoothstep(ecozone_fade_distance_m * 0.6, ecozone_fade_distance_m, view_distance);
	return mix(base_albedo, mixed, clamp(weight, 0.0, 1.0) * fade);
}
