shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// 카메라를 따라다니는 억새 필드. 격자 칸마다 억새 하나를 두고, 생태 구역 스플랫(억새·갈대 채널)
// 비율만큼만 세운다. 위치·회전·크기는 칸 좌표 해시로 고정되어 카메라가 움직여도 흔들리지 않는다.
// 생태 구역 범위 밖, 게임 수면(강·호수)·바다, 해수면 아래에는 세우지 않는다.
// 근경(card_mode=false): 18삼각형 다발. 원경(card_mode=true): 교차 카드 + 위에서 보이는 수평 카드,
// 윗부분을 물결 마루에 맞춰 조금씩 비틀어 들판 전체의 물결을 보인다.

#include "res://shaders/terrain_height.gdshaderinc"

uniform sampler2D eco_splat : filter_linear, repeat_disable;
uniform vec2 eco_uv_scale = vec2(0.000125);
uniform vec2 eco_uv_offset = vec2(0.5);
uniform sampler2D game_water : filter_linear, repeat_disable;
uniform bool has_game_water = false;
uniform float water_world_size = 80000.0;
uniform bool card_mode = false;
uniform sampler2D card_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float spacing = 0.9;
uniform float inner_radius = 0.0;
uniform float radius = 120.0;
uniform float thin_start = 50.0;
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

// 0~1: 이 칸을 세울 비율. 범위 밖·수면·해수면 아래는 0.
float cover_at(vec2 pos, out float grass, out float reed, out float ground) {
	vec2 uv = pos * eco_uv_scale + eco_uv_offset;
	grass = 0.0;
	reed = 0.0;
	ground = terrain_height(pos);
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return 0.0;
	}
	vec4 splat = textureLod(eco_splat, uv, 0.0);
	grass = splat.g;
	reed = splat.a * 0.85;
	float cover = max(grass, reed);
	if (has_game_water) {
		float water = textureLod(game_water, pos / water_world_size + vec2(0.5), 0.0).r;
		cover *= 1.0 - smoothstep(0.15, 0.35, water);
	}
	if (ground < 0.3) {
		cover = 0.0;
	}
	return cover;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 cell = floor(origin.xz / spacing + 0.5);
	float h1 = hash(cell);
	float h2 = hash(cell + 17.31);
	float h3 = hash(cell + 41.73);
	vec2 pos = (cell + (vec2(h1, h2) - 0.5) * 0.9) * spacing;
	float grass;
	float reed;
	float ground;
	float cover = cover_at(pos, grass, reed, ground);
	float d = length(pos - CAMERA_POSITION_WORLD.xz);
	float keep_ratio = cover * density * (1.0 - 0.65 * smoothstep(thin_start, radius, d));
	float alive = step(h3, keep_ratio) * step(d, radius) * step(inner_radius, d);
	float size = alive * (0.75 + 0.5 * h1) * (1.0 - smoothstep(radius * 0.8, radius, d));
	if (inner_radius > 0.0) {
		size *= smoothstep(inner_radius, inner_radius + spacing * 3.0, d);
	}

	// 풍향으로 진행하는 물결 + 직교 방향의 느린 돌풍 띠
	vec2 dir = normalize(wind_direction);
	vec2 across = vec2(-dir.y, dir.x);
	float phase = (dot(pos, dir) - TIME * wave_speed) / wave_length * 6.2831;
	float gust = 0.65 + 0.35 * sin(dot(pos, across) * 0.031 + TIME * 0.4);
	float crest = 0.5 + 0.5 * sin(phase + 0.6 * sin(dot(pos, across) * 0.05));
	float weight = card_mode ? COLOR.a : pow(COLOR.a, 1.5);
	float bend = weight * (0.18 + 0.82 * crest) * gust * sway_strength;
	float flutter = card_mode ? 0.0 : sin(TIME * 5.0 + h2 * 20.0) * 0.04 * weight;

	float angle = h2 * 6.2831;
	vec2 local = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xz;
	vec3 world = vec3(pos.x, ground - 0.05, pos.y);
	world += vec3(local.x, VERTEX.y, local.y) * size;
	world.xz += (dir * bend + across * flutter) * size;
	world.y -= bend * 0.35 * weight * size;
	VERTEX = world - origin;

	v_crest = crest * gust;
	v_plume = card_mode ? 0.0 : UV.x;
	vec3 base = card_mode ? vec3(1.0) : mix(stem_color, plume_color, UV.x);
	vec3 tint = card_mode ? mix(vec3(1.0), reed_color / plume_color, step(grass, reed)) : mix(base, reed_color, step(grass, reed));
	v_color = (card_mode ? tint : tint) * (0.88 + 0.24 * h1);
}

void fragment() {
	if (card_mode) {
		vec4 card = texture(card_texture, UV);
		if (card.a < 0.45) {
			discard;
		}
		// 밝은 이삭 텍셀이 물결 마루에서 더 밝아진다.
		float bright = smoothstep(0.6, 0.9, dot(card.rgb, vec3(0.333)));
		ALBEDO = card.rgb * v_color * (1.0 + bright * v_crest * 0.3);
	} else {
		// 마루에서 이삭이 빛을 받아 밝아진다(은빛 반짝임).
		ALBEDO = v_color * (1.0 + v_plume * v_crest * 0.35) + vec3(0.05) * v_plume * v_crest;
	}
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.35, 0.28, 0.12) * (card_mode ? 0.5 : v_plume);
}
