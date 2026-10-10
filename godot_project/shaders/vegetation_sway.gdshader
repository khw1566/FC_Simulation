shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 근경 식생(억새·갈대·대나무·수목) 공용. 정점 색을 알베도로 쓰고, 높이 제곱에 비례해 바람 방향으로 휜다.
// fade_far_m > 0이면 카메라 거리 fade_far_m ~ fade_far_m + fade_band_m 구간에서 디더로 사라져
// 같은 구간에서 나타나는 숲 덩어리·바닥 텍스처와 픽셀 단위로 겹치지 않고 교대한다.

uniform float sway_height_m = 2.4;
uniform float sway_strength_m = 0.28;
uniform float sway_speed = 1.6;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float gust_scale = 0.045;
uniform float fade_far_m = 0.0;
// 참이면 정점 색 알파를 흔들림 가중치로 쓴다(줄기 0, 수관 끝 1). 공통 숲 수목(forest_trees)용.
uniform bool use_vertex_weight = false;
uniform float fade_band_m = 20.0;

varying vec3 v_world;

float bayer4(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int index = x + y * 4;
	float pattern[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (pattern[index] + 0.5) / 16.0;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway_strength_m > 0.0) {
		float h = clamp(VERTEX.y / sway_height_m, 0.0, 1.0);
		float bend = use_vertex_weight ? COLOR.a * h : h * h;
		float phase = dot(world.xz, normalize(wind_direction)) * gust_scale * 6.2831;
		float wave = sin(TIME * sway_speed - phase) * 0.7 + sin(TIME * sway_speed * 2.7 - phase * 1.9 + world.x * 0.3) * 0.3;
		float gust = 0.6 + 0.4 * sin(TIME * 0.35 - phase * 0.25);
		vec3 local_dir = normalize(inverse(mat3(MODEL_MATRIX)) * vec3(wind_direction.x, 0.0, wind_direction.y));
		vec3 offset = local_dir * (wave * gust * sway_strength_m * bend);
		VERTEX.xz += offset.xz;
		VERTEX.y -= length(offset.xz) * 0.35 * h;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (fade_far_m > 0.0) {
		float d = length(CAMERA_POSITION_WORLD - v_world);
		float keep = 1.0 - smoothstep(fade_far_m, fade_far_m + fade_band_m, d);
		if (keep < bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
