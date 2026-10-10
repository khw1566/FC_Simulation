shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 카메라를 따라다니는 억새 필드. 격자 칸마다 억새 다발 하나를 두고, 생태 구역 스플랫(억새·갈대 채널)
// 비율만큼만 세운다. 위치·회전·크기는 칸 좌표 해시로 고정되어 카메라가 움직여도 흔들리지 않는다.
// 바람은 풍향을 따라 진행하는 파동이라 들판 전체가 물결치고, 파고(마루)에서 이삭이 밝게 반짝인다.

#include "res://shaders/terrain_height.gdshaderinc"

uniform sampler2D eco_splat : filter_linear, repeat_disable;
uniform vec2 eco_uv_scale = vec2(0.000125);
uniform vec2 eco_uv_offset = vec2(0.5);
uniform float spacing = 1.1;
uniform float radius = 130.0;
uniform float thin_start = 55.0;
uniform float density = 1.0;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float wave_length = 22.0;
uniform float wave_speed = 7.0;
uniform float sway_strength = 0.45;
uniform vec3 stem_color : source_color = vec3(0.70, 0.56, 0.29);
uniform vec3 plume_color : source_color = vec3(0.95, 0.84, 0.58);
uniform vec3 reed_color : source_color = vec3(0.50, 0.44, 0.26);

varying float v_crest;
varying float v_plume;
varying vec3 v_color;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 cell = floor(origin.xz / spacing + 0.5);
	float h1 = hash(cell);
	float h2 = hash(cell + 17.31);
	float h3 = hash(cell + 41.73);
	vec2 pos = (cell + (vec2(h1, h2) - 0.5) * 0.9) * spacing;
	vec4 splat = textureLod(eco_splat, pos * eco_uv_scale + eco_uv_offset, 0.0);
	float grass = splat.g;
	float reed = splat.a * 0.85;
	float cover = max(grass, reed);
	float d = length(pos - CAMERA_POSITION_WORLD.xz);
	float keep_ratio = cover * density * (1.0 - 0.65 * smoothstep(thin_start, radius, d));
	float alive = step(h3, keep_ratio) * step(d, radius);
	float size = alive * (0.75 + 0.5 * h1) * (1.0 - smoothstep(radius * 0.8, radius, d));

	// 풍향으로 진행하는 물결 + 직교 방향의 느린 돌풍 띠
	vec2 dir = normalize(wind_direction);
	vec2 across = vec2(-dir.y, dir.x);
	float phase = dot(pos, dir) / wave_length * 6.2831 - TIME * wave_speed / wave_length * 6.2831;
	float gust = 0.65 + 0.35 * sin(dot(pos, across) * 0.031 + TIME * 0.4);
	float crest = 0.5 + 0.5 * sin(phase + 0.6 * sin(dot(pos, across) * 0.05));
	float weight = pow(COLOR.a, 1.5);
	float bend = weight * (0.18 + 0.82 * crest) * gust * sway_strength;
	float flutter = sin(TIME * 5.0 + h2 * 20.0) * 0.04 * weight;

	float angle = h2 * 6.2831;
	vec2 local = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xz;
	vec3 world = vec3(pos.x, terrain_height(pos) - 0.05, pos.y);
	world += vec3(local.x, VERTEX.y, local.y) * size;
	world.xz += (dir * bend + across * flutter) * size;
	world.y -= bend * 0.35 * weight * size;
	VERTEX = world - origin;

	v_crest = crest * gust;
	v_plume = UV.x;
	vec3 base = mix(stem_color, plume_color, UV.x);
	v_color = mix(base, reed_color, step(grass, reed)) * (0.88 + 0.24 * h1);
}

void fragment() {
	// 마루에서 이삭이 빛을 받아 밝아진다(은빛 반짝임).
	ALBEDO = v_color * (1.0 + v_plume * v_crest * 0.35) + vec3(0.05) * v_plume * v_crest;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.35, 0.28, 0.12) * v_plume;
}
