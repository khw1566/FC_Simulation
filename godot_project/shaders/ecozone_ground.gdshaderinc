// 태화강 둔치 생태 구역 바닥 혼합 함수. 지형 셰이더에서 #include 후 albedo에 섞어 쓴다.
// 스플랫 A(R 잔디, G 억새, B 대숲 낙엽, A 수변 갈대), 스플랫 B(R 수림, G 들풀, A 둔치 평탄면).
// 좌표: 월드 미터, 원점은 지도 중앙, +X 동쪽, +Z 남쪽. 텍스처 원점(0,0)은 북서쪽.

uniform sampler2D ecozone_splat_a : filter_linear, repeat_disable;
uniform sampler2D ecozone_splat_b : filter_linear, repeat_disable;
uniform sampler2D ecozone_lawn : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_silvergrass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_bamboo_litter : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_reed_mud : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_woodland_soil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ecozone_meadow : source_color, filter_linear_mipmap, repeat_enable;
uniform float ecozone_world_size_m = 8000.0;
uniform float ecozone_tile_m = 6.0;
uniform float ecozone_fade_distance_m = 1800.0;

vec3 ecozone_blend(vec3 base_albedo, vec2 world_xz, float view_distance) {
	vec2 map_uv = world_xz / ecozone_world_size_m + 0.5;
	if (map_uv.x < 0.0 || map_uv.y < 0.0 || map_uv.x > 1.0 || map_uv.y > 1.0) {
		return base_albedo;
	}
	vec4 a = texture(ecozone_splat_a, map_uv);
	vec4 b = texture(ecozone_splat_b, map_uv);
	vec2 tile_uv = world_xz / ecozone_tile_m;
	vec3 mixed = texture(ecozone_lawn, tile_uv).rgb * a.r
		+ texture(ecozone_silvergrass, tile_uv).rgb * a.g
		+ texture(ecozone_bamboo_litter, tile_uv).rgb * a.b
		+ texture(ecozone_reed_mud, tile_uv).rgb * a.a
		+ texture(ecozone_woodland_soil, tile_uv).rgb * b.r
		+ texture(ecozone_meadow, tile_uv).rgb * b.g;
	float weight = a.r + a.g + a.b + a.a + b.r + b.g;
	if (weight < 0.001) {
		return base_albedo;
	}
	float fade = 1.0 - smoothstep(ecozone_fade_distance_m * 0.6, ecozone_fade_distance_m, view_distance);
	return mix(base_albedo, mixed / weight, clamp(weight, 0.0, 1.0) * fade);
}
