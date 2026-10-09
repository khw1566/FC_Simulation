shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 억새·갈대·대나무 근경 흔들림. 정점 색을 알베도로 쓰고, 높이 제곱에 비례해 바람 방향으로 휜다.
// MultiMesh 인스턴스마다 월드 위치로 위상을 달리해 군락 전체가 물결치듯 움직인다.

uniform float sway_height_m = 2.4;
uniform float sway_strength_m = 0.28;
uniform float sway_speed = 1.6;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float gust_scale = 0.045;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / sway_height_m, 0.0, 1.0);
	float bend = h * h;
	float phase = dot(world.xz, normalize(wind_direction)) * gust_scale * 6.2831;
	float wave = sin(TIME * sway_speed - phase) * 0.7 + sin(TIME * sway_speed * 2.7 - phase * 1.9 + world.x * 0.3) * 0.3;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 - phase * 0.25);
	vec3 local_dir = normalize(inverse(mat3(MODEL_MATRIX)) * vec3(wind_direction.x, 0.0, wind_direction.y));
	vec3 offset = local_dir * (wave * gust * sway_strength_m * bend);
	VERTEX.xz += offset.xz;
	VERTEX.y -= length(offset.xz) * 0.35 * h;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
