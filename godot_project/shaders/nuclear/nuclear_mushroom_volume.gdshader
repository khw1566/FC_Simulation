shader_type spatial;
// 핵폭발 한 건의 모든 볼륨(화구 → 토러스 버섯갓 → 먼지 기둥 → 얼음 모자·응결 고리, 지면 먼지 파도)과
// 지형 위를 쓸고 가는 충격파 먼지 띠를 한 번의 레이마칭으로 합성한다.
// 볼륨을 패스 하나로 묶어 겹친 부분의 그리기 순서가 프레임마다 바뀌며 깜박이는 문제를 없앤다.
// 화면 전체 1회 그리기이며 지형 가림은 깊이 텍스처로 직접 처리한다.
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "nuclear_volume_common.gdshaderinc"

uniform vec3 burst_origin = vec3(0.0);
uniform float ground_height = 0.0;
uniform vec3 cap_center = vec3(0.0, 100.0, 0.0);
uniform float cap_radius = 100.0;
uniform float cap_half_height = 100.0;
// 0: 구형 화구, 1: 밑면이 오목한 버섯갓
uniform float form = 0.0;
// 토러스 순환 위상(rad): 안쪽은 솟고 바깥쪽은 말려 내려간다.
uniform float roll_phase = 0.0;
uniform float luminosity = 1.0;
uniform float stem_radius = 50.0;
uniform float stem_top = 0.0;
uniform float stem_rise_speed = 30.0;
// 기둥 축의 높이별 수평 변위(지면 0 ~ stem_level_height, 8단): 고도별 바람에 따라 굽는다.
uniform vec2 stem_offsets[8];
uniform float stem_level_height = 1000.0;
// 밀도 1일 때 소광 계수(1/m): 갓은 공통 extinction, 기둥과 지면 먼지는 각자의 두께에 맞춘다.
uniform float stem_extinction = 0.004;
uniform float pileus_alpha = 0.0;
// 기존 구름층 고도의 응결 고리: x 고도, y 반두께, z 세기
uniform vec4 collar_a = vec4(0.0);
uniform vec4 collar_b = vec4(0.0);
uniform float cloud_alpha = 1.0;
uniform float debris_age = 0.0;
uniform float water_burst = 0.0;
// 지면 먼지 파도(기저 서지)와 후폭풍 유입
uniform float surge_radius = 100.0;
uniform float surge_height = 100.0;
uniform float surge_alpha = 0.0;
uniform float surge_extinction = 0.01;
uniform float inflow_offset = 0.0;
uniform vec3 dust_color : source_color = vec3(0.62, 0.55, 0.46);
// 지형 표면을 쓸고 가는 충격파 먼지 띠(원거리까지)
uniform float shock_radius = 0.0;
uniform float shock_width = 50.0;
uniform float shock_strength = 0.0;

void vertex() {
	// QuadMesh(2x2)를 화면 전체에 고정한다. 원거리 면 절단 없이 70km 규모 구름도 그린다.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// 높이별 기둥 축: 고도별 바람 변위를 따라 굽고, 갓 밑에서는 바람에 밀린 갓 중심으로 합류한다.
vec2 stem_axis(float y) {
	float h = y - ground_height;
	float f = clamp(h / max(stem_level_height, 1.0), 0.0, 1.0) * 7.0;
	int i = min(int(f), 6);
	vec2 off = mix(stem_offsets[i], stem_offsets[i + 1], f - float(i));
	float merge = smoothstep(0.82, 1.0, h / max(cap_center.y - ground_height, 1.0));
	return mix(burst_origin.xz + off, cap_center.xz, merge);
}

// 갓 타원체 거리(1이 표면). 버섯 단계에서는 기둥이 들어오는 밑면 가운데가 오목해진다.
float cap_ellipse(vec3 q, out float rho) {
	rho = length(q.xz);
	float yy = q.y;
	if (yy < 0.0) {
		yy -= form * cap_half_height * 0.7 * (1.0 - smoothstep(0.0, 0.7 * cap_radius, rho));
	}
	return length(vec2(rho / cap_radius, yy / cap_half_height));
}

// 토러스 순환면(중심 원 둘레의 자오면)에서 잡음 좌표를 ang만큼 돌려 읽는다.
float cap_noise(vec2 v, vec2 dir, float rt, float ang, vec3 offset) {
	float cs = cos(ang);
	float sn = sin(ang);
	vec2 vr = vec2(cs * v.x - sn * v.y, sn * v.x + cs * v.y);
	vec3 nq = vec3(dir.x * (rt + vr.x), vr.y, dir.y * (rt + vr.x)) / cap_radius + offset;
	float n = texture(shape_noise, nq * 0.9).r;
	return n * 0.68 + (1.0 - texture(detail_noise, nq * 3.1).r) * 0.32;
}

float cap_field(vec3 p, out float core) {
	vec3 q = p - cap_center;
	float rho;
	float e = cap_ellipse(q, rho);
	core = e;
	if (e > 1.45) { return 0.0; }
	float rt = cap_radius * 0.55 * form;
	vec2 v = vec2(rho - rt, q.y * cap_radius / max(cap_half_height, 1.0));
	float minor = length(v);
	vec2 dir = rho > 0.001 ? q.xz / rho : vec2(1.0, 0.0);
	// 흐름 잡음: 큰 회전각을 그대로 쓰면 좌표가 접혀 동심 줄무늬가 생기므로,
	// 반 주기 어긋난 두 층을 작은 각도(±0.45rad)만 돌리며 교차 페이드해 연속된 말림처럼 보이게 한다.
	float cycle = roll_phase / 0.9;
	float pa = fract(cycle);
	float pb = fract(cycle + 0.5);
	vec3 drift = vec3(0.0, anim_time * 0.0004, 0.0);
	float na = cap_noise(v, dir, rt, (pa - 0.5) * 0.9, drift + vec3(floor(cycle) * 0.37));
	float nb = cap_noise(v, dir, rt, (pb - 0.5) * 0.9, drift + vec3(floor(cycle + 0.5) * 0.37 + 0.5));
	float wa = 1.0 - abs(2.0 * pa - 1.0);
	float n = mix(nb, na, wa);
	// 두 층 평균으로 줄어든 대비를 되돌린다.
	n = 0.5 + (n - 0.5) * (1.0 + 0.4 * (1.0 - abs(2.0 * wa - 1.0)));
	core = mix(e, minor / max(cap_radius * 0.45, 1.0), form);
	// 표면을 잡음으로 크게 부풀리고 깎아 콜리플라워 같은 덩어리 윤곽을 만든다.
	float shape = (1.0 - e) * 1.8 + (n - 0.5) * 2.2 * mix(0.35, 1.0, form);
	return clamp(shape * 2.5, 0.0, 1.0);
}

float stem_field(vec3 p, out float foot) {
	foot = 0.0;
	float h = p.y - ground_height;
	if (stem_top <= 1.0 || h < -stem_radius || p.y > stem_top + stem_radius * 2.0) { return 0.0; }
	float span = max(cap_center.y - ground_height, 1.0);
	vec2 off = p.xz - stem_axis(p.y);
	float r = length(off);
	foot = exp(-max(h, 0.0) / max(span * 0.04, 25.0));
	float merge = smoothstep(0.6, 1.0, h / span);
	float sr = stem_radius * (1.0 + 1.2 * foot + 1.6 * merge);
	if (r > sr * 1.6) { return 0.0; }
	// 상승 기류와 유입 소용돌이를 따라 잡음을 이동한다.
	float swirl = anim_time * 0.03 + h * 0.0002;
	float cs = cos(swirl);
	float sn = sin(swirl);
	vec2 rot = vec2(cs * off.x - sn * off.y, sn * off.x + cs * off.y);
	vec3 nq = vec3(rot.x, h - anim_time * stem_rise_speed, rot.y) / max(stem_radius * 2.6, 30.0);
	float n = texture(shape_noise, nq).r * 0.75 + (1.0 - texture(detail_noise, nq * 3.1).r) * 0.25;
	// 중심부는 잡음과 무관하게 차 있어 가까이서 보아도 기둥이 끊기지 않는다.
	float radial = 1.0 - r / sr + (n - 0.5) * 0.7;
	float fill = 1.0 - smoothstep(stem_top - stem_radius * 1.5, stem_top + stem_radius * 0.5, p.y + (n - 0.5) * stem_radius * 2.0);
	return clamp(radial * 3.0, 0.0, 1.0) * fill * mix(0.7, 1.0, foot);
}

// 빠르게 솟는 머리 위 습윤층이 들려 생기는 얇은 얼음 모자
float pileus_field(vec3 p) {
	if (pileus_alpha <= 0.001) { return 0.0; }
	vec3 q = p - cap_center;
	float e = length(vec2(length(q.xz) / (cap_radius * 1.22), (q.y - cap_half_height * 0.2) / (cap_half_height * 1.15)));
	float n = texture(shape_noise, q / (cap_radius * 0.8)).r;
	float shell = exp(-pow((e - 1.0 + (n - 0.5) * 0.05) / 0.045, 2.0)) * smoothstep(0.0, cap_half_height * 0.5, q.y);
	return shell * pileus_alpha * 0.7;
}

// 기둥이 기존 구름층을 관통하며 생기는 응결 고리(스커트)
float collar_field(vec3 p, vec4 deck) {
	if (deck.z <= 0.001 || stem_top < deck.x) { return 0.0; }
	float dy = abs(p.y - deck.x) / max(deck.y, 30.0);
	if (dy > 1.0) { return 0.0; }
	float r = length(p.xz - stem_axis(p.y));
	float inner = stem_radius * 1.05;
	float outer = stem_radius * 3.4;
	float n = texture(shape_noise, p / (stem_radius * 2.2) + vec3(anim_time * 0.001)).r;
	float ring = smoothstep(inner, inner * 1.5, r) * (1.0 - smoothstep(outer * 0.65, outer, r + (n - 0.5) * stem_radius * 1.2));
	return ring * (1.0 - dy * dy) * deck.z * smoothstep(0.32, 0.6, n);
}

float surge_field(vec3 p) {
	if (surge_alpha < 0.002) { return 0.0; }
	float h = p.y - ground_height;
	vec2 off = p.xz - burst_origin.xz;
	float r = length(off);
	if (r > surge_radius * 1.15 || h < -surge_height * 0.5 || h > surge_height * 2.0) { return 0.0; }
	vec2 dir = r > 0.01 ? off / r : vec2(1.0, 0.0);
	float behind = surge_radius - r;
	// 전면은 낮게 말리고 안쪽으로 갈수록 두껍게 솟는다.
	float local_h = surge_height * (0.25 + 0.75 * smoothstep(0.0, surge_radius * 0.35 + 50.0, behind));
	vec2 adv = p.xz + dir * inflow_offset;
	// 큰 규모 잡음으로 먼지 더미 높이와 전면 윤곽을 들쭉날쭉하게 한다.
	float lump = texture(shape_noise, vec3(adv.x, 0.0, adv.y) / max(surge_radius * 0.35, 200.0)).r;
	local_h *= 0.45 + 1.1 * lump;
	behind += (lump - 0.5) * surge_radius * 0.25;
	vec3 nq = vec3(adv.x, h * 1.5, adv.y) / max(surge_height * 2.0, 60.0);
	float n = texture(shape_noise, nq + vec3(0.0, -anim_time * 0.002, 0.0)).r * 0.7;
	n += (1.0 - texture(detail_noise, nq * 3.3).r) * 0.3;
	float vertical = 1.0 - smoothstep(local_h * 0.3, local_h, h + (n - 0.5) * local_h * 0.8);
	vertical *= smoothstep(-surge_height * 0.5, 0.0, h);
	float front = smoothstep(0.0, surge_radius * 0.05 + 20.0, behind + (n - 0.5) * surge_radius * 0.06);
	float rolling = 0.55 + 0.45 * exp(-behind / (surge_radius * 0.12 + 40.0));
	return clamp(vertical * front * rolling * smoothstep(0.28, 0.6, n) * 1.3, 0.0, 1.0) * surge_alpha;
}

// 합성 소광 계수(1/m)와 반사색·발광 비율·갓 깊이·환경광 높이
float field(vec3 p, out vec3 albedo, out float hot, out float depth_in, out float up) {
	float core;
	float foot;
	float cap = cap_field(p, core);
	float stem = stem_field(p, foot);
	float extra = pileus_field(p) + collar_field(p, collar_a) + collar_field(p, collar_b);
	float surge = surge_field(p);
	float s_cap = cap * extinction * cloud_alpha;
	float s_stem = stem * stem_extinction * cloud_alpha;
	float s_extra = extra * extinction * cloud_alpha;
	float s_surge = surge * surge_extinction;
	float sigma = s_cap + s_stem + s_extra + s_surge;
	albedo = vec3(0.0);
	hot = 0.0;
	depth_in = 0.0;
	up = 0.5;
	if (sigma <= 0.0) { return 0.0; }
	// 초기의 적갈색(질소산화물)에서 수증기가 응결하며 회백색으로 바뀐다.
	vec3 cap_col = mix(vec3(0.46, 0.27, 0.17), vec3(0.80, 0.78, 0.75), smoothstep(0.08, 0.6, debris_age));
	vec3 stem_col = mix(vec3(0.55, 0.47, 0.38), vec3(0.64, 0.57, 0.48), foot);
	stem_col = mix(stem_col, vec3(0.86, 0.88, 0.9), water_burst);
	albedo = (cap_col * s_cap + stem_col * s_stem + vec3(0.95, 0.96, 0.98) * s_extra + dust_color * s_surge) / sigma;
	// 뜨거울수록 갓 전체가, 식을수록 토러스 중심부만 빛난다.
	float edge = mix(0.12, 1.15, heat);
	hot = (s_cap / sigma) * (1.0 - smoothstep(edge * 0.6, edge, core));
	// 갓 안쪽 깊이(0 표면 ~ 1 중심): 환경광 차폐에 쓴다.
	depth_in = (s_cap / sigma) * clamp(1.0 - core, 0.0, 1.0) + (s_stem / sigma) * 0.3;
	float up_cap = clamp((p.y - cap_center.y) / max(cap_half_height, 1.0) * 0.5 + 0.5, 0.0, 1.0);
	float up_surge = clamp((p.y - ground_height) / max(surge_height, 1.0), 0.0, 1.0);
	up = (up_cap * (s_cap + s_extra) + 0.45 * s_stem + up_surge * s_surge) / sigma;
	return sigma;
}

// 태양 그림자용 저가 소광 계수(잡음 없음)
float coarse(vec3 p) {
	float rho;
	float e = cap_ellipse(p - cap_center, rho);
	float sigma = clamp((1.0 - e) * 3.0, 0.0, 1.0) * extinction;
	if (p.y < stem_top) {
		float r = length(p.xz - stem_axis(p.y));
		sigma += clamp((1.0 - r / stem_radius) * 2.0, 0.0, 1.0) * 0.6 * stem_extinction;
	}
	return sigma * cloud_alpha;
}

// 한 구간을 적분해 누적 색·투과율을 갱신한다.
void march(vec3 cam, vec3 rd, float t0, float t1, int steps, float jitter, float phase, vec3 hot_color, inout float transmit, inout vec3 acc) {
	float ds = (t1 - t0) / float(steps);
	for (int i = 0; i < 96; i++) {
		if (i >= steps || transmit < 0.01) { break; }
		float t = t0 + (float(i) + jitter) * ds;
		vec3 p = cam + rd * t;
		vec3 albedo;
		float hot;
		float depth_in;
		float up;
		float sigma = field(p, albedo, hot, depth_in, up);
		if (sigma < 0.0000005) { continue; }
		float od = 0.0;
		float reach = max(min(cap_radius, stem_radius * 2.0) * 0.12, 20.0);
		for (int j = 0; j < 3; j++) {
			if (j >= light_steps) { break; }
			od += coarse(p + sun_direction * reach) * reach * 1.6;
			reach *= 2.4;
		}
		// 다중 산란 근사: 짧은 감쇠 + 긴 꼬리
		float sunlit = exp(-od * 0.6) * 0.8 + exp(-od * 0.1) * 0.2;
		float occlusion = mix(1.0, 0.45, depth_in);
		vec3 lit = albedo * (ambient_color * mix(0.2, 0.75, up) * occlusion + sun_color * sunlit * phase);
		// 내부 고온부의 복사가 갓 밑면과 기둥 상부, 지면 먼지를 붉게 비춘다.
		lit += albedo * nv_fireball_light(p);
		float clear_air = nv_haze(t, rd.y);
		lit = mix(haze_color, lit, clear_air);
		vec3 emit = hot_color * luminosity * hot * sqrt(clear_air);
		float a = 1.0 - exp(-sigma * ds);
		acc += transmit * a * (lit + emit);
		transmit *= 1.0 - a;
	}
}

// 지형 표면 위 충격파 먼지 띠: 전면에서 짙고 뒤로 엷게 끌린다(높이와 무관하게 표면을 따라간다).
void shock_ground(vec3 cam, vec3 rd, float opaque, inout float transmit, inout vec3 acc) {
	if (shock_strength < 0.002 || opaque > 1.0e8) { return; }
	vec3 s = cam + rd * opaque;
	float r = length(s.xz - burst_origin.xz);
	float x = (r - shock_radius) / max(shock_width, 1.0);
	float band = exp(-x * x);
	float trail = r < shock_radius ? exp(-(shock_radius - r) / (shock_width * 8.0)) * 0.35 : 0.0;
	float n = texture(shape_noise, vec3(s.x, 0.0, s.z) / max(shock_width * 6.0, 200.0)).r;
	float a = clamp(shock_strength * (band + trail) * (0.6 + 0.8 * n), 0.0, 0.85);
	if (a < 0.002) { return; }
	vec3 col = dust_color * 1.3 * (ambient_color * 0.8 + sun_color * 0.75 * smoothstep(-0.05, 0.25, sun_direction.y));
	col += dust_color * nv_fireball_light(s);
	col = mix(haze_color, col, nv_haze(opaque, rd.y));
	acc += transmit * a * col;
	transmit *= 1.0 - a;
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 rd = nv_view_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float opaque = nv_opaque_distance(SCREEN_UV, INV_PROJECTION_MATRIX);
	// 빈 공간이 대부분인 큰 상자 대신 갓 타원체·기둥 상자·지면 먼지 판 구간에만 표본을 몰아 층상 띠를 없앤다.
	vec2 spans[3];
	int count = 0;
	vec2 cap_span = nv_ellipsoid_hit(cam, rd, cap_center, vec3(cap_radius * 1.45, cap_half_height * 1.5, cap_radius * 1.45));
	if (cloud_alpha > 0.001 && min(cap_span.y, opaque) > cap_span.x) {
		spans[count] = vec2(cap_span.x, min(cap_span.y, opaque));
		count += 1;
	}
	if (cloud_alpha > 0.001 && stem_top > 1.0) {
		float foot = stem_radius * 3.6;
		vec2 lo_xz = min(burst_origin.xz, cap_center.xz);
		vec2 hi_xz = max(burst_origin.xz, cap_center.xz);
		for (int k = 0; k < 8; k++) {
			lo_xz = min(lo_xz, burst_origin.xz + stem_offsets[k]);
			hi_xz = max(hi_xz, burst_origin.xz + stem_offsets[k]);
		}
		vec3 stem_lo = vec3(lo_xz.x - foot, ground_height - stem_radius, lo_xz.y - foot);
		vec3 stem_hi = vec3(hi_xz.x + foot, stem_top + stem_radius * 2.0, hi_xz.y + foot);
		vec2 stem_span = nv_aabb_hit(cam, rd, stem_lo, stem_hi);
		if (min(stem_span.y, opaque) > stem_span.x) {
			spans[count] = vec2(stem_span.x, min(stem_span.y, opaque));
			count += 1;
		}
	}
	if (surge_alpha > 0.002) {
		float sr = surge_radius * 1.15;
		vec3 surge_lo = vec3(burst_origin.x - sr, ground_height - surge_height * 0.5, burst_origin.z - sr);
		vec3 surge_hi = vec3(burst_origin.x + sr, ground_height + surge_height * 2.0, burst_origin.z + sr);
		vec2 surge_span = nv_aabb_hit(cam, rd, surge_lo, surge_hi);
		if (min(surge_span.y, opaque) > surge_span.x) {
			spans[count] = vec2(surge_span.x, min(surge_span.y, opaque));
			count += 1;
		}
	}
	// 시작 거리순 정렬 후 겹치는 구간은 합친다.
	for (int a = 0; a < 2; a++) {
		for (int b = 0; b < 2; b++) {
			if (b + 1 < count && spans[b].x > spans[b + 1].x) {
				vec2 tmp = spans[b];
				spans[b] = spans[b + 1];
				spans[b + 1] = tmp;
			}
		}
	}
	vec2 merged[3];
	int merged_count = 0;
	float total = 0.0;
	for (int k = 0; k < 3; k++) {
		if (k >= count) { break; }
		if (merged_count > 0 && spans[k].x <= merged[merged_count - 1].y) {
			merged[merged_count - 1].y = max(merged[merged_count - 1].y, spans[k].y);
		} else {
			merged[merged_count] = spans[k];
			merged_count += 1;
		}
	}
	for (int k = 0; k < 3; k++) {
		if (k >= merged_count) { break; }
		total += merged[k].y - merged[k].x;
	}
	float jitter = nv_bayer(FRAGCOORD.xy);
	float mu = dot(rd, sun_direction);
	// 태양 쪽에서 볼 때 가장자리가 밝게 빛나는 전방 산란
	float phase = 0.75 + 0.9 * pow(max(mu, 0.0), 6.0);
	vec3 hot_color = nv_heat_color(heat);
	float transmit = 1.0;
	vec3 acc = vec3(0.0);
	for (int k = 0; k < 3; k++) {
		if (k >= merged_count) { break; }
		float share = (merged[k].y - merged[k].x) / max(total, 0.001);
		int steps = clamp(int(float(step_count) * share), 8, 96);
		march(cam, rd, merged[k].x, merged[k].y, steps, jitter, phase, hot_color, transmit, acc);
	}
	shock_ground(cam, rd, opaque, transmit, acc);
	float alpha = 1.0 - transmit;
	if (alpha < 0.003) { discard; }
	ALBEDO = acc;
	ALPHA = alpha;
}
