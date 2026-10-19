// 핵폭발 볼륨 공통: 깊이 복원, 상자·타원체 교차, 순서 지터, 화구 발광색, 조명 입력.
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D shape_noise : repeat_enable, filter_linear;
uniform sampler3D detail_noise : repeat_enable, filter_linear;
// 전처리기 대신 생성 시 실제 렌더러의 깊이 좌표 규약을 전달한다.
uniform bool compatibility_depth = false;
uniform int step_count = 48;
uniform int light_steps = 2;
// 밀도 1일 때의 소광 계수(1/m). 구름 크기에 맞춰 CPU가 정한다.
uniform float extinction = 0.004;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color = vec3(1.0);
uniform vec3 ambient_color = vec3(0.55, 0.6, 0.68);
uniform vec3 haze_color = vec3(0.68, 0.76, 0.86);
uniform float haze_density = 0.000028;
uniform float anim_time = 0.0;
// 화구 섬광·잔열이 주변 구름과 먼지를 비추는 빛
uniform vec3 fireball_position = vec3(0.0);
uniform float heat = 1.0;
uniform float glow_strength = 0.0;
uniform float glow_radius = 1000.0;

float nv_bayer(vec2 frag) {
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	const float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

// 불투명 지오메트리까지의 광선 거리(m). 하늘이면 매우 큰 값.
float nv_opaque_distance(vec2 screen_uv, mat4 inv_projection) {
	float depth = texture(scene_depth, screen_uv).r;
	if (depth <= 0.000001) { return 1.0e9; }
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
	if (compatibility_depth) {
		ndc.z = depth * 2.0 - 1.0;
	}
	vec4 vp = inv_projection * vec4(ndc, 1.0);
	return length(vp.xyz / vp.w);
}

// 화면 UV의 월드 광선 방향
vec3 nv_view_ray(vec2 screen_uv, mat4 inv_projection, mat4 inv_view) {
	vec4 far_view = inv_projection * vec4(screen_uv * 2.0 - 1.0, 0.5, 1.0);
	return normalize((inv_view * vec4(far_view.xyz / far_view.w, 0.0)).xyz);
}

// 임의 상자 진입·이탈 거리. 카메라가 안쪽이면 진입 거리는 0.
vec2 nv_aabb_hit(vec3 ro, vec3 rd, vec3 lo, vec3 hi) {
	vec3 safe = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), rd)) * max(abs(rd), vec3(0.000001));
	vec3 t0 = (lo - ro) / safe;
	vec3 t1 = (hi - ro) / safe;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	return vec2(max(max(tn.x, tn.y), max(tn.z, 0.0)), min(min(tf.x, tf.y), tf.z));
}

// 타원체 진입·이탈 거리. 맞지 않으면 x > y.
vec2 nv_ellipsoid_hit(vec3 ro, vec3 rd, vec3 center, vec3 radii) {
	vec3 o = (ro - center) / radii;
	vec3 d = rd / radii;
	float a = dot(d, d);
	float b = dot(o, d);
	float disc = b * b - a * (dot(o, o) - 1.0);
	if (disc <= 0.0) { return vec2(1.0, 0.0); }
	float s = sqrt(disc);
	return vec2(max((-b - s) / a, 0.0), (-b + s) / a);
}

// 냉각 순서: 백색 → 황색 → 주황 → 적색 → 암적색 (NuclearTimeline.heat_color와 동일)
vec3 nv_heat_color(float h) {
	vec3 c = mix(vec3(0.35, 0.05, 0.01), vec3(0.95, 0.25, 0.04), smoothstep(0.05, 0.3, h));
	c = mix(c, vec3(1.0, 0.58, 0.18), smoothstep(0.3, 0.5, h));
	c = mix(c, vec3(1.0, 0.86, 0.55), smoothstep(0.5, 0.75, h));
	return mix(c, vec3(1.0, 0.98, 0.95), smoothstep(0.75, 0.95, h));
}

// 대기 안개 투과율. haze_density는 카메라 고도로 이미 감쇠된 값이므로
// 높이 규모 8km 지수 대기를 따라 광선 경사만큼 적분한다(높은 구름일수록 선명하다).
float nv_haze(float t, float dir_y) {
	float x = clamp(t * dir_y / 8000.0, -10.0, 60.0);
	float f = abs(x) < 0.0001 ? 1.0 : (1.0 - exp(-x)) / x;
	return exp(-haze_density * t * f);
}

// 화구에서 오는 직접광(섬광 + 잔열 발광)
vec3 nv_fireball_light(vec3 p) {
	vec3 d = p - fireball_position;
	float r2 = glow_radius * glow_radius;
	return nv_heat_color(heat) * glow_strength * r2 / (r2 + dot(d, d));
}
