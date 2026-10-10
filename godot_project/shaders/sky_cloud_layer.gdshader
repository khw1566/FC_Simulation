shader_type spatial;
// 화면 전체 1회 그리기로 월드 고정 구름층을 레이마칭한다.
// 지평선(최대 70km)까지 이어지는 적운·층운·적란운 슬래브와 고고도 권운 평면을 한 패스에 합성한다.
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform sampler2D weather_noise : repeat_enable, filter_linear_mipmap;
uniform sampler3D base_noise : repeat_enable, filter_linear;
uniform sampler3D detail_noise : repeat_enable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool compatibility_depth = false;

// 바람으로 누적된 표본 이동량(m). 저층과 권운층은 서로 다른 고도풍을 따른다.
uniform vec2 wind_offset = vec2(0.0);
uniform vec2 cirrus_offset = vec2(0.0);
uniform vec2 cirrus_wind_dir = vec2(1.0, 0.0);
uniform float evolve = 0.0;

// 유형별 덮임 비율(0~1)과 고도(m)
uniform float cu_coverage = 0.0;
uniform float cu_base = 1100.0;
uniform float cu_top = 2700.0;
uniform float st_coverage = 0.0;
uniform float st_base = 800.0;
uniform float st_top = 2000.0;
uniform float cb_coverage = 0.0;
uniform float cb_base = 650.0;
uniform float cb_top = 11000.0;
// 중층 고층운(4~5km): 비·뇌우 때 적란운 허리를 감싼다.
uniform float as_coverage = 0.0;
uniform float as_base = 4000.0;
uniform float as_top = 5600.0;
uniform float ci_coverage = 0.0;
uniform float ci_altitude = 9200.0;
uniform float slab_bottom = 600.0;
uniform float slab_top = 3000.0;

// 품질 예산
uniform int step_count = 32;
uniform int light_steps = 2;
uniform float detail_distance = 5000.0;
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

float remap01(float v, float lo, float hi) {
	return clamp((v - lo) / max(hi - lo, 0.0001), 0.0, 1.0);
}

// 반복문 안에서는 미분 기반 밉 선택이 불안정하므로 명시적 LOD로 읽는다.
float wtex(vec2 uv) {
	return textureLod(weather_noise, uv, 0.0).r;
}

// 표본 간격(m)에 맞춰 기상도를 미리 흐리게 읽는다. 원경의 긴 간격에서 작은 구름을 건너뛰며 생기는 자글거림을 막는다.
float wtex_filtered(vec2 uv, float tile_m, float stride) {
	float lod = clamp(log2(max(stride, 1.0) / (tile_m / 512.0)) - 1.0, 0.0, 8.0);
	return textureLod(weather_noise, uv, lod).r;
}

// 2D 기상도: x=적운 셀, y=층운 덮개, z=고층운 덮개, w=탑 높이 변화
vec4 weather_at(vec2 xz, float stride) {
	float large = wtex_filtered(xz * (1.0 / 42000.0), 42000.0, stride);
	float mid = wtex_filtered(xz * (1.0 / 6500.0) + vec2(0.37, 0.71), 6500.0, stride);
	float cu = 0.0;
	if (cu_coverage > 0.001) {
		// 큰 규모 기상도가 적운 밀집 지역과 맑은 지역을 나눈다.
		float lo = 1.0 - clamp(cu_coverage * (0.55 + 0.9 * large), 0.0, 1.0);
		cu = remap01(mid, lo, lo + 0.4);
	}
	float st = 0.0;
	if (st_coverage > 0.001) {
		float lo_s = 1.0 - st_coverage;
		st = smoothstep(lo_s, lo_s + 0.35, large * 0.6 + mid * 0.4);
	}
	if (cb_coverage > 0.001) {
		// 뇌우 때 낮은 덮개구름은 폭풍 세포 주변에만 빽빽하고 그 밖은 끊겨 탑이 보인다.
		float lo_n = 1.0 - cb_coverage * 0.6;
		float near = smoothstep(lo_n, lo_n + 0.3, wtex(xz * (1.0 / 30000.0) + vec2(0.13, 0.52)));
		st *= mix(1.0, 0.2 + 0.8 * near, cb_coverage);
	}
	float alto = 0.0;
	if (as_coverage > 0.001) {
		float lo_m = 1.0 - as_coverage;
		alto = smoothstep(lo_m, lo_m + 0.55, large * 0.55 + (1.0 - mid) * 0.45);
	}
	return vec4(cu, st, alto, mix(0.45, 1.0, large));
}

// 3D 밀도. hfrac에는 지배 유형 기준 상대 높이를 돌려준다.
float density_at(vec3 p, vec4 w, float dist, bool detailed, out float hfrac) {
	hfrac = 0.0;
	float h_cu = (p.y - cu_base) / (cu_top - cu_base);
	// 평평한 밑면과 위로 갈수록 좁아지는 돔(콜리플라워) 윤곽
	float prof_cu = smoothstep(0.0, 0.07, h_cu) * (1.0 - smoothstep(0.0, w.w, h_cu) * 0.85);
	float c_cu = w.x * prof_cu * step(h_cu, w.w);

	float h_st = (p.y - st_base) / (st_top - st_base);
	float prof_st = smoothstep(0.0, 0.12, h_st) * (1.0 - smoothstep(0.5 + 0.4 * w.w, 1.0, h_st));
	float c_st = w.y * prof_st;

	float h_as = (p.y - as_base) / (as_top - as_base);
	float c_as = w.z * smoothstep(0.0, 0.35, h_as) * (1.0 - smoothstep(0.45 + 0.3 * w.w, 1.0, h_as));

	float c_cb = 0.0;
	float h_cb = (p.y - cb_base) / (cb_top - cb_base);
	if (cb_coverage > 0.001 && h_cb > 0.0 && h_cb < 1.08) {
		// 여러 층을 관통하는 적란운: 저층 밑면에서 대류권계면(약 11km)까지 솟은 탑,
		// 고도별 크기가 다른 탑 마루(터렛), 꼭대기에서 바람 방향으로 퍼지는 모루와 탑 위로 솟는 돔.
		float hc = clamp(h_cb, 0.0, 1.0);
		vec2 cxz = p.xz + wind_offset - cirrus_wind_dir * hc * 1800.0;
		float cbv = wtex(cxz * (1.0 / 30000.0) + vec2(0.13, 0.52));
		float turret = texture(base_noise, vec3(cxz.x, p.y * 1.6, cxz.y) * (1.0 / 9000.0)).r - 0.5;
		float lo_t = 1.0 - cb_coverage * 0.42 + 0.10 * hc - turret * 0.22;
		float tower = smoothstep(lo_t, lo_t + 0.24, cbv) * smoothstep(0.0, 0.03, h_cb) * (1.0 - smoothstep(0.84, 0.97, h_cb));
		float spread = smoothstep(0.78, 1.0, hc);
		float cbv_anvil = wtex((cxz - cirrus_wind_dir * spread * 9000.0) * (1.0 / 30000.0) + vec2(0.13, 0.52));
		float lo_a = 1.0 - cb_coverage * 0.62;
		float anvil = smoothstep(lo_a, lo_a + 0.3, cbv_anvil) * smoothstep(0.80, 0.90, h_cb) * (1.0 - smoothstep(0.95, 1.0, h_cb)) * 0.75;
		float overshoot = smoothstep(lo_t + 0.2, lo_t + 0.32, cbv) * smoothstep(0.9, 0.97, h_cb) * (1.0 - smoothstep(1.0, 1.07, h_cb));
		c_cb = max(max(tower, anvil), overshoot);
	}

	float c = max(max(c_cu, c_as), max(c_st, c_cb));
	if (c <= 0.002) {
		return 0.0;
	}
	float type_scale = 1.0;
	hfrac = clamp(h_cu, 0.0, 1.0);
	if (c_st >= c) {
		type_scale = 0.6;
		hfrac = clamp(h_st, 0.0, 1.0);
	}
	if (c_as >= c) {
		type_scale = 0.45;
		hfrac = clamp(h_as, 0.0, 1.0);
	}
	if (c_cb >= c) {
		type_scale = 2.5;
		hfrac = clamp(h_cb, 0.0, 1.0);
	}

	vec3 q = vec3(p.x + wind_offset.x, p.y, p.z + wind_offset.y);
	vec3 uvw = q * (1.0 / 3200.0) + vec3(0.0, evolve, 0.0);
	float base = texture(base_noise, uvw).r;
	float billow = 1.0 - texture(detail_noise, uvw).r;
	float shape = base * 0.5 + billow * 0.5;
	float d = remap01(shape, 1.0 - c, 1.0) * c;
	// 원경 LOD: 성긴 표본에서 자글거림이 생기지 않도록 고주파 형상을 기상도 윤곽으로 부드럽게 바꾼다.
	float lod = smoothstep(8000.0, 30000.0, dist);
	d = mix(d, c * smoothstep(0.2, 0.75, c) * 0.75, lod);
	if (detailed && d > 0.0 && dist < detail_distance) {
		// 가장자리만 깎아 솜털 같은 경계를 만든다.
		float det = texture(detail_noise, uvw * 7.0 + vec3(evolve * 3.0)).r;
		float erode = (1.0 - det) * 0.3 * (1.0 - dist / detail_distance);
		d = remap01(d, erode, 1.0);
	}
	return d * type_scale;
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
	bool is_sky = compatibility_depth ? depth >= 0.999999 : depth <= 0.000001;
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

	// 2. 고고도 권운 2층: 9.2km 섬유상 권운(갈고리 꼬리) + 7.8km 얇은 권적운/권층운 조각
	if (ci_coverage > 0.001 && abs(dir.y) > 0.00001) {
		for (int layer = 0; layer < 2; layer++) {
			// 카메라에서 먼 층부터 그려 앞쪽 층이 위에 덮이도록 한다.
			int idx = (cam.y < ci_altitude - 700.0) ? 1 - layer : layer;
			float alt = idx == 0 ? ci_altitude : ci_altitude - 1400.0;
			float tc = (alt - cam.y) / dir.y;
			if (tc <= 0.0 || tc >= opaque || tc >= max_distance * 1.5) { continue; }
			vec2 xz = (cam + dir * tc).xz + cirrus_offset * (idx == 0 ? 1.0 : 0.85);
			vec2 perp = vec2(-cirrus_wind_dir.y, cirrus_wind_dir.x);
			float along = dot(xz, cirrus_wind_dir);
			float across = dot(xz, perp);
			// 원경일수록 밉을 올려 가는 줄무늬가 깜빡이지 않게 한다.
			float lod_c = clamp(log2(max(tc, 1.0) / 5000.0) + 1.0, 0.0, 6.0);
			float a = 0.0;
			if (idx == 0) {
				float n1 = textureLod(weather_noise, vec2(along / 42000.0, across / 9000.0), lod_c * 0.5).r;
				// 영역 왜곡으로 끝이 휘어진 갈고리 모양 섬유
				// 완만한 굽음만 주어 거의 평행한 섬유가 끝에서 휘도록 한다.
				float bend = (n1 - 0.5) * 1600.0;
				float strands = textureLod(weather_noise, vec2(along / 30000.0, (across + bend) / 1500.0) + vec2(0.31, 0.17), lod_c).r;
				float fine = textureLod(weather_noise, vec2(along / 14000.0, (across + bend * 1.3) / 420.0) + vec2(0.7, 0.4), lod_c + 1.0).r;
				float lo = 1.0 - ci_coverage * 0.62;
				float body = smoothstep(lo, lo + 0.35, n1);
				a = body * smoothstep(0.35, 0.8, strands * 0.65 + fine * 0.35) * 0.55;
			} else {
				float m1 = textureLod(weather_noise, xz / 26000.0 + vec2(0.52, 0.09), lod_c * 0.5).r;
				float m2 = textureLod(weather_noise, xz / 1800.0 + vec2(0.11, 0.83), lod_c).r;
				float lo2 = 1.0 - ci_coverage * 0.4;
				a = smoothstep(lo2, lo2 + 0.3, m1) * smoothstep(0.35, 0.75, m2) * 0.3;
			}
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
