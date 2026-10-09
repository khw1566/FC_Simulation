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
uniform float ecozone_tile_m = 6.0;
uniform float ecozone_fade_distance_m = 6000.0;

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
	// 근경은 6m 반복, 원경은 4배 큰 반복을 섞어 타일 반복 무늬를 줄인다.
	vec2 near_uv = world_xz / ecozone_tile_m;
	vec2 far_uv = world_xz / (ecozone_tile_m * 4.0);
	float far_mix = smoothstep(80.0, 400.0, view_distance);
	vec3 lawn = mix(texture(ecozone_lawn, near_uv).rgb, texture(ecozone_lawn, far_uv).rgb, far_mix);
	vec3 grass = mix(texture(ecozone_silvergrass, near_uv).rgb, texture(ecozone_silvergrass, far_uv).rgb, far_mix);
	vec3 litter = texture(ecozone_bamboo_litter, near_uv).rgb;
	vec3 reed = mix(texture(ecozone_reed_mud, near_uv).rgb, texture(ecozone_reed_mud, far_uv).rgb, far_mix);
	vec3 soil = texture(ecozone_woodland_soil, near_uv).rgb;
	vec3 meadow = mix(texture(ecozone_meadow, near_uv).rgb, texture(ecozone_meadow, far_uv).rgb, far_mix);
	vec3 mixed = (lawn * a.r + grass * a.g + litter * a.b + reed * a.a + soil * b.r + meadow * b.g) / weight;
	float fade = 1.0 - smoothstep(ecozone_fade_distance_m * 0.6, ecozone_fade_distance_m, view_distance);
	return mix(base_albedo, mixed, clamp(weight, 0.0, 1.0) * fade);
}
