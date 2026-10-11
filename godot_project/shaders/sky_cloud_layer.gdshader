shader_type spatial;
// 화면 전체 1회 그리기로 월드 고정 구름층을 레이마칭한다.
// 지평선(최대 70km)까지 이어지는 적운·층운·적란운 슬래브와 고고도 권운 평면을 한 패스에 합성한다.
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled;

#include "optics/cloud_field.gdshaderinc"
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool compatibility_depth = false;

// 품질 예산
uniform int step_count = 32;
uniform int light_steps = 2;
uniform float light_distance = 25000.0;
uniform float refine_stride = 70.0;
uniform float max_distance = 70000.0;
uniform float extinction = 0.04;

// 조명
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color = vec3(1.0);
uniform float ambient_scale = 1.0;
uniform vec4 cloud_top_color : source_color = vec4(0.96, 0.97, 1.0, 1.0);
uniform vec4 cloud_bottom_color : source_color = vec4(0.60, 0.65, 0.73, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.30, 0.32, 0.38, 1.0);
uniform vec3 haze_color = vec3(0.68, 0.76, 0.86);
uniform float haze_density = 0.000028;

void vertex() {
	// QuadMesh(2x2)를 화면 전체에 고정한다.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float wlod(vec2 uv, float lod) {
	return textureLod(weather_noise, uv, lod).r;
}

// 한 방향 섬유 무늬. 좌표를 픽셀마다 회전하면 먼 좌표에서 등고선 무늬가 생기므로 방향은 고정값을 쓴다.
float fibers_dir(vec2 xz, float lod, vec2 d, vec2 seed) {
	float along = dot(xz, d);
	float across = dot(xz, vec2(-d.y, d.x));
	// 약한 굽힘만: 강하면 대리석 같은 등고선 무늬가 된다.
	float bend = (wlod(xz / 16000.0 + seed.yx, lod * 0.5) - 0.5) * 700.0;
	float strands = wlod(vec2(along / 22000.0, (across + bend) / 1800.0) + seed * 1.7, lod);
	float fine = wlod(vec2(along / 9000.0, across / 800.0) + seed * 2.3, lod + 1.0);
	// 가는 결은 옅은 바탕 위에 얹어 털 같은 줄 대신 부드러운 섬유로 보이게 한다.
	float soft = smoothstep(0.3, 0.75, wlod(vec2(along / 30000.0, across / 4000.0) + seed * 0.7, lod * 0.5));
	return mix(soft * 0.6, smoothstep(0.42, 0.85, strands * 0.85 + fine * 0.15), 0.45);
}

// 결 방향이 지역마다 다른 섬유상 권운: 고정된 세 방향 무늬를 약 50km 규모 지역 가중치로 섞는다.
float cirrus_fibratus(vec2 xz, float lod, vec2 seed) {
	float r = wlod(xz / 50000.0 + seed, lod * 0.3);
	float g = wlod(xz / 43000.0 + seed.yx + vec2(0.4, 0.1), lod * 0.3);
	// 한 지역에는 한 방향이 지배하도록 가중치를 날카롭게 한다 (여러 방향이 겹치면 격자무늬가 된다).
	vec3 wgt = vec3(smoothstep(0.45, 0.7, r), smoothstep(0.45, 0.7, g), 0.3) + 0.001;
	wgt = wgt * wgt * wgt * wgt;
	wgt /= wgt.x + wgt.y + wgt.z;
	float f0 = fibers_dir(xz, lod, vec2(0.966, 0.259), seed);
	float f1 = fibers_dir(xz, lod, vec2(-0.259, 0.966), seed + vec2(0.21, 0.37));
	float f2 = fibers_dir(xz, lod, vec2(0.574, -0.819), seed + vec2(0.53, 0.11));
	return f0 * wgt.x + f1 * wgt.y + f2 * wgt.z;
}

// 상층(약 9.2km): 섬유상 권운 두 계열(서로 다른 방향) + 뭉친 농밀권운 + 옅은 권층운 막
float cirrus_upper(vec2 xz, float lod) {
	float lo = 1.0 - ci_coverage * 0.62;
	float gate = smoothstep(lo, lo + 0.35, wlod(xz / 38000.0, lod * 0.5));
	float type_a = smoothstep(0.35, 0.7, wlod(xz / 60000.0 + vec2(0.21, 0.64), lod * 0.3));
	float type_b = smoothstep(0.4, 0.75, wlod(xz / 52000.0 + vec2(0.77, 0.12), lod * 0.3));
	float fib1 = cirrus_fibratus(xz, lod, vec2(0.13, 0.41)) * type_a;
	float fib2 = cirrus_fibratus(xz, lod, vec2(0.58, 0.83)) * (1.0 - type_a) * 0.8;
	// 농밀권운: 등방성 덩어리, 가장자리가 부드럽다.
	float spissatus = smoothstep(0.55, 0.85, wlod(xz / 6000.0 + vec2(0.35, 0.92), lod) * 0.7 + wlod(xz / 1800.0 + vec2(0.66, 0.27), lod + 0.5) * 0.3) * type_b;
	float veil = smoothstep(0.3, 0.75, wlod(xz / 24000.0 + vec2(0.48, 0.55), lod * 0.5)) * 0.18;
	return gate * clamp(max(max(fib1, fib2) * 0.55, spissatus * 0.5) + veil, 0.0, 0.7);
}

// 하층(약 7.8km): 잔물결 권적운 알갱이 + 짧은 꼬리 권운 조각
float cirrus_lower(vec2 xz, float lod) {
	float lo = 1.0 - ci_coverage * 0.42;
	float gate = smoothstep(lo, lo + 0.3, wlod(xz / 26000.0 + vec2(0.52, 0.09), lod * 0.5));
	// 권적운: 물결 방향이 지역마다 다른 알갱이 줄
	float rsel = smoothstep(0.4, 0.6, wlod(xz / 50000.0 + vec2(0.9, 0.3), lod * 0.3));
	float warp = wlod(xz / 3000.0, lod) * 6.0;
	float ripple = 0.5 + 0.5 * mix(sin(dot(xz, vec2(0.8, 0.6)) / 260.0 + warp), sin(dot(xz, vec2(-0.5, 0.866)) / 260.0 + warp), rsel);
	float grains = smoothstep(0.5, 0.78, wlod(xz / 900.0 + vec2(0.11, 0.83), lod + 0.5) * 0.6 + ripple * 0.4 * smoothstep(3.0, 0.0, lod));
	float cc = grains * smoothstep(0.45, 0.7, wlod(xz / 9000.0 + vec2(0.3, 0.6), lod * 0.5));
	float wisps = cirrus_fibratus(xz, lod, vec2(0.37, 0.19)) * smoothstep(0.55, 0.8, wlod(xz / 15000.0 + vec2(0.05, 0.71), lod * 0.5));
	return gate * clamp(cc * 0.32 + wisps * 0.35, 0.0, 0.5);
}

float bayer4(vec2 frag) {
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	const float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

float hg(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566 * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.0001), 1.5));
}

vec3 shade(vec3 p, vec4 w, float d, float hfrac, float dist, float phase) {
	float sunlit = mix(0.35, 1.0, hfrac);
	if (light_steps > 0 && dist < light_distance) {
		float od = 0.0;
		float reach = 60.0;
		for (int j = 0; j < 3; j++) {
			if (j >= light_steps) { break; }
			float hf_unused;
			od += density_at(p + sun_direction * reach, w, dist, false, hf_unused) * reach * 2.0;
			reach *= 3.0;
		}
		// 다중 산란 근사: 짧은 감쇠 + 긴 꼬리
		sunlit = exp(-extinction * od) * 0.75 + exp(-extinction * od * 0.15) * 0.25;
	}
	vec3 ambient = mix(cloud_bottom_color.rgb, cloud_top_color.rgb, hfrac) * ambient_scale * mix(1.0, 0.65, clamp(d, 0.0, 1.0));
	// 날씨 팔레트는 그늘(환경광)에만 강하게 적용: 폭풍 구름도 햇빛 받는 꼭대기는 희다.
	vec3 sun = sun_color * mix(vec3(1.0), cloud_top_color.rgb, 0.3) * sunlit * phase;
	vec3 color = ambient * 0.72 + sun * 0.85;
	return mix(cloud_shadow_color.rgb * ambient_scale, color, clamp(sunlit * 1.4 + hfrac * 0.4, 0.0, 1.0));
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec4 far_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(far_view.xyz / far_view.w, 0.0)).xyz);

	// 불투명 지오메트리까지의 거리
	float depth = texture(scene_depth, SCREEN_UV).r;
	float opaque = 1.0e9;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	if (compatibility_depth) {
		ndc.z = depth * 2.0 - 1.0;
	}
	bool is_sky = depth <= 0.000001;
	if (!is_sky) {
		vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		opaque = length(vp.xyz / vp.w);
	}

	float transmit = 1.0;
	vec3 acc = vec3(0.0);
	float mu = dot(dir, sun_direction);
	float phase = clamp(mix(hg(mu, 0.6), hg(mu, -0.25), 0.3) * 12.566, 0.0, 4.0);
	phase = mix(1.0, phase, 0.55);
	// 4x4 베이어 순서 지터: 백색 잡음보다 반짝임이 적고 해상도에서 거의 보이지 않는다.
	float jitter = bayer4(FRAGCOORD.xy);
	float sub_jitter = fract(jitter * 7.31 + 0.37);

	// 1. 저·중층 슬래브
	float t0 = 0.0;
	float t1 = -1.0;
	if (abs(dir.y) > 0.00001) {
		float ta = (slab_bottom - cam.y) / dir.y;
		float tb = (slab_top - cam.y) / dir.y;
		t0 = max(min(ta, tb), 0.0);
		t1 = max(ta, tb);
	} else if (cam.y > slab_bottom && cam.y < slab_top) {
		t1 = max_distance;
	}
	t1 = min(t1, min(opaque, max_distance));
	if (t1 > t0 && slab_top > slab_bottom) {
		float span = t1 - t0;
		// 지평선 쪽 긴 광선(화면의 작은 띠)에만 표본을 최대 2배까지 더 준다.
		int n_steps = int(clamp(float(step_count) * span / 12000.0, float(step_count), min(64.0, float(step_count) * 2.0)));
		float steps = float(n_steps);
		bool prev_hit = false;
		for (int i = 0; i < 64; i++) {
			if (i >= n_steps || transmit < 0.02) { break; }
			// 1차: 앞쪽이 촘촘한 2차 간격으로 구간 중앙만 값싸게 검사
			float s0 = (float(i) + jitter) / steps;
			float s1 = (float(i) + 1.0 + jitter) / steps;
			float t = t0 + span * s0 * s0;
			float ds = span * (s1 * s1 - s0 * s0);
			vec3 pm = cam + dir * (t + ds * 0.5);
			vec4 w = weather_at(pm.xz + wind_offset, max(ds * 0.25, refine_stride));
			float hf_probe;
			bool hit = density_at(pm, w, t, false, hf_probe) > 0.002;
			if (!hit && !prev_hit) { continue; }
			prev_hit = hit;
			// 2차: 구름이 있는 구간만 잘게 나눠 지터 표본으로 적분 (가장자리 계단 제거)
			int sub = clamp(int(ceil(ds / refine_stride)), 1, 4);
			float sds = ds / float(sub);
			for (int k = 0; k < 4; k++) {
				if (k >= sub) { break; }
				float ts = t + (float(k) + sub_jitter) * sds;
				vec3 p = cam + dir * ts;
				float hfrac;
				float d = density_at(p, w, ts, true, hfrac);
				if (d > 0.002) {
					vec3 col = shade(p, w, d, hfrac, ts, phase);
					col = mix(col, haze_color * ambient_scale, 1.0 - exp(-ts * haze_density));
					// 원경은 소광을 낮춰 여러 표본이 평균되도록 해 반짝임을 줄인다.
					float ext = extinction * mix(1.0, 0.4, smoothstep(8000.0, 35000.0, ts));
					float a = (1.0 - exp(-ext * d * sds)) * (1.0 - smoothstep(max_distance * 0.75, max_distance, ts));
					acc += transmit * a * col;
					transmit *= 1.0 - a;
					if (transmit < 0.02) { break; }
				}
			}
		}
	}

	// 2. 고고도 권운 2층: 여러 권운 형태를 지역별로 섞는다 (단일 방향 줄무늬 금지)
	if (ci_coverage > 0.001 && abs(dir.y) > 0.00001) {
		for (int layer = 0; layer < 2; layer++) {
			// 카메라에서 먼 층부터 그려 앞쪽 층이 위에 덮이도록 한다.
			int idx = (cam.y < ci_altitude - 700.0) ? 1 - layer : layer;
			float alt = idx == 0 ? ci_altitude : ci_altitude - 1400.0;
			float tc = (alt - cam.y) / dir.y;
			if (tc <= 0.0 || tc >= opaque || tc >= max_distance * 1.5) { continue; }
			vec2 xz = (cam + dir * tc).xz + cirrus_offset * (idx == 0 ? 1.0 : 0.85);
			// 원경일수록 밉을 올려 가는 결이 깜빡이지 않게 한다.
			float lod_c = clamp(log2(max(tc, 1.0) / 5000.0) + 1.0, 0.0, 6.0);
			float a = idx == 0 ? cirrus_upper(xz, lod_c) : cirrus_lower(xz, lod_c);
			a *= mix(0.25, 1.0, smoothstep(0.0, 0.1, abs(dir.y))) * (1.0 - smoothstep(max_distance, max_distance * 1.5, tc));
			if (a < 0.002) { continue; }
			// 얼음 결정: 태양 쪽 전방 산란이 강하고 그늘이 거의 없다.
			vec3 col = mix(vec3(1.0), cloud_top_color.rgb, 0.25) * (sun_color * (0.45 + phase * 0.55) + vec3(0.5) * ambient_scale);
			col = mix(col, haze_color * ambient_scale, 1.0 - exp(-tc * haze_density * 0.4));
			if (cam.y < alt) {
				acc += transmit * a * col;
			} else {
				acc = a * col + (1.0 - a) * acc;
			}
			transmit *= 1.0 - a;
		}
	}

	float alpha = 1.0 - transmit;
	if (alpha < 0.002) {
		discard;
	}
	ALBEDO = acc;
	ALPHA = alpha;
}
