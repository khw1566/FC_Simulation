// 바다 수면 평면(kanmon_water)과 지형 위 하천 수면(procedural_terrain)이 함께 쓰는 단일 수면 표현.
// 색·물결·반사를 한 곳에서 정의해 하구에서 두 수면이 만나도 경계가 드러나지 않게 한다.
// 얕은물 띠는 같은 수계 마스크 커버리지(smooth_water_mask)로, 먼바다 짙은 색은 수심으로만 정한다.

const vec3 WATER_DEEP_COLOR = vec3(0.035, 0.16, 0.25);
const vec3 WATER_SHALLOW_COLOR = vec3(0.10, 0.29, 0.34);
const vec3 WATER_OPEN_SEA_COLOR = vec3(0.025, 0.12, 0.21);
const vec3 WATER_FOAM_COLOR = vec3(0.66, 0.77, 0.78);

// 렌더링 전용 수계 부호 거리장(hydro/water_sdf.png): 128 기준, ±40m, 수면 안쪽 음수.
// 마스크 화소(약 14m)보다 좁은 하천도 끊기지 않고 경계가 계단 없이 이어진다.
const float WATER_SDF_CLAMP_M = 40.0;
// 지형 제거·바다 평면 허용을 가르는 거리. 바다 평면은 이보다 0.5m 넓게 그려 틈을 막는다.
const float WATER_SDF_ZONE_M = 3.0;

float decode_water_sdf(float encoded) {
	return (encoded * 255.0 - 128.0) / 127.0 * WATER_SDF_CLAMP_M;
}

// 화면 미분(fwidth)으로 경계 폭을 잡아 거리와 무관하게 1화소 안티앨리어싱한다.
float water_sdf_alpha(float distance_m, float screen_width_m) {
	float aa = max(screen_width_m * 0.75, 0.25);
	return 1.0 - smoothstep(-aa, aa, distance_m);
}

// 얕은물 띠를 기슭에서 안쪽 14m까지로 둔다(water_shore_factor 입력 범위로 변환).
float water_sdf_shading_coverage(float distance_m) {
	return mix(0.35, 1.0, smoothstep(0.0, 14.0, -distance_m));
}

// coverage: smooth_water_mask 결과(0~1), depth_m: 수면 아래 지형까지 깊이(모르면 0)
float water_shore_factor(float coverage) {
	return 1.0 - smoothstep(0.35, 0.95, coverage);
}

vec3 water_surface_color(float coverage, float depth_m, vec2 world_xz, float time) {
	float shore = water_shore_factor(coverage);
	vec3 color = mix(WATER_DEEP_COLOR, WATER_SHALLOW_COLOR, shore);
	// 수심 4m 이하는 하천과 같은 색을 유지하고 그보다 깊은 바다만 서서히 짙게 한다.
	color = mix(color, WATER_OPEN_SEA_COLOR, smoothstep(4.0, 25.0, depth_m) * (1.0 - shore));
	vec2 p = world_xz * 0.035;
	float foam = shore * (0.5 + 0.5 * sin(p.x * 0.6 + p.y + time * 0.35));
	return mix(color, WATER_FOAM_COLOR, foam * 0.18);
}

vec3 water_surface_normal(vec2 world_xz, float time, float view_distance) {
	vec2 p = world_xz * 0.035;
	float phase = time * 0.35;
	float a = sin(p.x + phase) * cos(p.y * 0.8 + phase * 0.7);
	float b = cos(p.x * 1.6 - phase * 0.6) * sin(p.y * 1.3 + phase);
	float weight = (1.0 - smoothstep(1000.0, 10000.0, view_distance)) * 0.045;
	return normalize(vec3(a * weight, 1.0, b * weight));
}

float water_surface_roughness(float coverage, float view_distance) {
	return mix(mix(0.30, 0.46, water_shore_factor(coverage)), 0.55, smoothstep(10000.0, 20000.0, view_distance));
}

float water_surface_specular(float view_distance) {
	return mix(0.35, 0.12, smoothstep(10000.0, 20000.0, view_distance));
}
