// 구름 렌더링·지면 그림자·광선이 공유하는 월드 밀도장.
#include "blast_field.gdshaderinc"
#include "wind_field.gdshaderinc"
uniform sampler2D weather_noise : repeat_enable, filter_linear_mipmap;
uniform sampler3D base_noise : repeat_enable, filter_linear;
uniform sampler3D detail_noise : repeat_enable, filter_linear;

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

uniform float detail_distance = 5000.0;

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
// 국지 바람으로 밀린 위치의 기상도. 밀도장 호출 전에 이것으로 기상도를 읽는다.
vec4 cloud_weather(vec3 p, float stride) {
	return weather_at(cloud_warp(p).xz + wind_offset, stride);
}

// p_world는 실제 월드 위치. 형상 표본은 국지 바람 변위(cloud_warp)를 적용한 위치에서 읽고,
// 폭발 소산·충격파 효과는 실제 위치 기준으로 계산한다.
float density_at(vec3 p_world, vec4 w, float dist, bool detailed, out float hfrac) {
	hfrac = 0.0;
	vec3 p = cloud_warp(p_world);
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

	float c_type = max(max(c_cu, c_as), max(c_st, c_cb));
	float c = c_type;
	if (blast_count > 0 && c > 0.002) {
		c = min(c * blast_density_scale(p_world), 1.5);
	}
	if (c <= 0.002) {
		return 0.0;
	}
	float type_scale = 1.0;
	hfrac = clamp(h_cu, 0.0, 1.0);
	if (c_st >= c_type) {
		type_scale = 0.6;
		hfrac = clamp(h_st, 0.0, 1.0);
	}
	if (c_as >= c_type) {
		type_scale = 0.45;
		hfrac = clamp(h_as, 0.0, 1.0);
	}
	if (c_cb >= c_type) {
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

