shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ============================================================
// 고품질·비정형·상호작용 볼류메트릭 구름 셰이더 (Worley-Perlin & Cavity)
// ============================================================

// 품질 모드: 0=Ultra (32스텝, 다중산란), 1=High (18스텝), 2=Medium (10스텝), 3=Laptop/Low (5스텝, 경량)
uniform int   quality_mode    : hint_range(0, 3)        = 1;

uniform float cloud_density   : hint_range(0.1, 30.0)  = 6.0;
uniform float noise_scale     : hint_range(0.5, 20.0)  = 3.2;
uniform float detail_scale    : hint_range(1.0, 40.0)  = 7.5;
uniform float coverage        : hint_range(0.0, 1.0)    = 0.52;
uniform float time_speed      : hint_range(0.0, 0.5)    = 0.025;
uniform int   march_steps     : hint_range(4, 36)       = 16;
uniform int   light_steps     : hint_range(0, 4)        = 2;

// 구름 유형 (0: Cumulus 적운, 1: Stratocumulus 층적운, 2: Cirrus 권운, 3: Cumulonimbus 적란운)
uniform int   cloud_type      : hint_range(0, 3)        = 0;
uniform float puffiness       : hint_range(0.1, 3.0)    = 1.1; // 뭉침 응집도
uniform float curl_factor     : hint_range(0.0, 2.0)    = 0.6; // 대류 및 결 왜곡

uniform vec4  cloud_top_color    : source_color = vec4(0.96, 0.97, 1.0, 1.0);
uniform vec4  cloud_bottom_color : source_color = vec4(0.60, 0.65, 0.76, 1.0);
uniform vec4  cloud_shadow_color : source_color = vec4(0.24, 0.27, 0.36, 1.0);

uniform vec3  sun_direction   = vec3(0.35, -0.75, 0.25);
uniform float sun_absorption  : hint_range(0.0, 5.0)  = 1.8;
uniform float ambient_light   : hint_range(0.0, 1.0)  = 0.22;
uniform float night_weight    : hint_range(0.0, 1.0)  = 0.0;
uniform float moonlight_scale : hint_range(0.0, 1.0)  = 1.0;
uniform float forward_scatter : hint_range(0.0, 0.99) = 0.55;

// ============================================================
// 기체 물리 상호작용 (Wake Cavity & Jet Wash Trench)
// ============================================================
uniform vec3  player_pos_obj       = vec3(999.0);
uniform vec3  player_vel_obj       = vec3(0.0);
uniform float player_wake_radius   = 0.0;
uniform float player_wake_strength = 0.0;

// ============================================================
// 노이즈 함수군 (Worley Cellular + Value Noise + Curl Vector)
// ============================================================
float hash3(vec3 p) {
	p  = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i + vec3(0,0,0)), hash3(i + vec3(1,0,0)), u.x),
			mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), u.x),
			mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), u.x), u.y), u.z);
}

// Worley (Cellular) 노이즈: 솜사탕 모양의 둥글둥글한 응결핵 표현
float worley_noise(vec3 p) {
	vec3 id = floor(p);
	vec3 fd = fract(p);
	float min_dist = 1.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 cell_point = hash33(id + neighbor);
				vec3 diff = neighbor + cell_point - fd;
				min_dist = min(min_dist, length(diff));
			}
		}
	}
	return clamp(min_dist, 0.0, 1.0);
}

float fbm_value(vec3 p) {
	float v = 0.0;
	float a = 0.52;
	vec3 shift = vec3(100.0);
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.05 + shift;
		a *= 0.48;
	}
	return v;
}

// Worley-Perlin 하이브리드 합성 (구름 기본 골격)
float worley_perlin_fbm(vec3 p) {
	float f = fbm_value(p);
	float w = 1.0 - worley_noise(p * 0.85);
	return mix(f, w, 0.42);
}

// 3차원 Curl 대류 벡터장 (Boiling Effect)
vec3 curl_vector(vec3 p) {
	float dx = sin(p.y * 3.5 + p.z * 2.0);
	float dy = cos(p.z * 3.5 + p.x * 2.0);
	float dz = sin(p.x * 3.5 + p.y * 2.0);
	return vec3(dy - dz, dz - dx, dx - dy) * 0.35;
}

// ============================================================
// 밀도 샘플러 (Worley-Perlin + 구면 마스킹 + 상호작용 후류 터널)
// ============================================================
float sample_density(vec3 pos, float wind_time) {
	// 1. 박스 모서리 단절 원천 제거: 구면 지수 마스킹 (Anti-Cube Spherical Mask)
	float dist_sq = dot(pos, pos);
	if (dist_sq > 0.24) {
		return 0.0;
	}
	float sphere_falloff = smoothstep(0.48, 0.20, sqrt(dist_sq));

	// 2. 비행체 통과 후류 터널 (Wake Cavity)
	float wake_atten = 1.0;
	if (player_wake_strength > 0.01) {
		float dist_to_player = length(pos - player_pos_obj);
		if (dist_to_player < player_wake_radius) {
			float wake_t = dist_to_player / max(player_wake_radius, 0.001);
			wake_atten = mix(0.0, 1.0, smoothstep(0.0, 1.0, wake_t) * (1.0 - player_wake_strength * 0.9));
		}
	}

	float vert_t = clamp(pos.y + 0.5, 0.0, 1.0);
	float d = 0.0;

	// 동적 대류 벡터 (품질 모드가 노트북일 경우 생략하여 경량화)
	vec3 boiling = vec3(0.0);
	if (quality_mode < 3) {
		boiling = curl_vector(pos * 1.8 + vec3(0.0, wind_time * 0.4, 0.0)) * curl_factor;
	}

	// 유형 0: Cumulus (적운 - 뭉게구름)
	if (cloud_type == 0) {
		float base_flatness = smoothstep(0.02, 0.18, vert_t);
		float top_dome = smoothstep(0.98, 0.42, vert_t);
		float vertical_profile = base_flatness * top_dome;

		vec3 p_noise = (pos + boiling) * noise_scale + vec3(wind_time * 0.4, wind_time * 0.1, wind_time * 0.2);
		float raw_noise = (quality_mode >= 2) ? fbm_value(p_noise) : worley_perlin_fbm(p_noise);
		float billow = 1.0 - abs(raw_noise * 2.0 - 1.0);
		float puff_val = mix(raw_noise, billow, puffiness * 0.65);

		float detail = 0.0;
		if (quality_mode <= 1) {
			vec3 det_p = pos * detail_scale + vec3(wind_time * 0.8, 0.0, wind_time * 0.4);
			detail = value_noise(det_p) * 0.18;
		}

		d = (puff_val - (1.0 - coverage) * 0.48 + detail) * vertical_profile;
	}
	// 유형 1: Stratocumulus (층적운 - 넓고 평평한 파도형 덮개구름)
	else if (cloud_type == 1) {
		float vertical_profile = smoothstep(0.02, 0.22, vert_t) * smoothstep(0.98, 0.72, vert_t);
		vec3 p_noise = vec3(pos.x * 0.7, pos.y * 2.5, pos.z * 0.7) * noise_scale + vec3(wind_time * 0.35, 0.0, wind_time * 0.15) + boiling * 0.4;
		float base = fbm_value(p_noise) - (1.0 - coverage) * 0.48;
		d = base * vertical_profile;
	}
	// 유형 2: Cirrus (권운 - 고고도 얇은 빗자루 결)
	else if (cloud_type == 2) {
		float vertical_profile = smoothstep(0.05, 0.35, vert_t) * smoothstep(0.95, 0.65, vert_t);
		vec3 warp = vec3(sin(pos.z * 6.0 + wind_time * 0.5) * curl_factor, 0.0, cos(pos.x * 6.0) * curl_factor);
		vec3 p_noise = (pos + warp) * vec3(0.5, 3.2, 2.0) * noise_scale;
		float raw = fbm_value(p_noise);
		float streak = pow(raw, 2.0);
		d = (streak - (1.0 - coverage) * 0.42) * vertical_profile * 0.85;
	}
	// 유형 3: Cumulonimbus (적란운 - 거대 먹구름 및 모루 구조)
	else {
		float vertical_profile = smoothstep(0.01, 0.12, vert_t);
		float anvil_spread = 1.0 + smoothstep(0.62, 0.98, vert_t) * 1.4;
		float radial_dist = (length(pos.xz) / anvil_spread) * 2.0;
		float radial_mask = smoothstep(1.0, 0.15, radial_dist);

		vec3 p_noise = (pos + boiling * 0.7) * noise_scale + vec3(wind_time * 0.25, wind_time * 0.15, 0.0);
		float raw_noise = (quality_mode >= 2) ? fbm_value(p_noise) : worley_perlin_fbm(p_noise);
		float billow = 1.0 - abs(raw_noise * 2.0 - 1.0);
		float puff_val = mix(raw_noise, billow, puffiness);

		float detail = 0.0;
		if (quality_mode <= 1) {
			vec3 det_p = pos * detail_scale;
			detail = value_noise(det_p) * 0.25;
		}

		d = (puff_val - (1.0 - coverage) * 0.42 + detail) * vertical_profile * radial_mask * 1.45;
	}

	return max(0.0, d) * cloud_density * sphere_falloff * wake_atten;
}

// Henyey-Greenstein 위상 함수
float hg_phase(float cos_theta, float g) {
	float g2    = g * g;
	float denom = 1.0 + g2 - 2.0 * g * cos_theta;
	return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

// Ray-AABB 교점 계산
bool ray_box_intersect(vec3 ro, vec3 rd, out float t_near, out float t_far) {
	vec3 inv  = 1.0 / (rd + sign(rd) * 0.000001);
	vec3 t0   = (-0.5 - ro) * inv;
	vec3 t1   = ( 0.5 - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	t_near = max(max(tmin.x, tmin.y), tmin.z);
	t_far  = min(min(tmax.x, tmax.y), tmax.z);
	return (t_far > max(t_near, 0.0));
}

// 태양 광원 투과 마칭
float light_march(vec3 pos, vec3 light_dir_obj, float wind_time, int active_lsteps) {
	if (active_lsteps <= 0) {
		return 1.0;
	}
	float t_near, t_far;
	bool hit = ray_box_intersect(pos, light_dir_obj, t_near, t_far);
	float optical_depth = 0.0;
	if (hit) {
		float ls = (t_far - max(t_near, 0.0)) / float(active_lsteps);
		vec3 lp = pos;
		for (int i = 0; i < active_lsteps; i++) {
			lp += light_dir_obj * ls;
			optical_depth += sample_density(lp, wind_time) * ls;
		}
	}
	return exp(-optical_depth * sun_absorption);
}

varying vec3 v_obj_cam_pos;
varying vec3 v_obj_vert_pos;
varying vec3 v_sun_obj;

void vertex() {
	mat4 inv_model = inverse(MODEL_MATRIX);
	vec3 cam_world = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_obj_cam_pos  = (inv_model * vec4(cam_world, 1.0)).xyz;
	v_obj_vert_pos = VERTEX;
	v_sun_obj      = normalize((inv_model * vec4(normalize(sun_direction), 0.0)).xyz);
}

void fragment() {
	vec3 ro = v_obj_cam_pos;
	vec3 rd = normalize(v_obj_vert_pos - v_obj_cam_pos);

	float t_near, t_far;
	bool hit = ray_box_intersect(ro, rd, t_near, t_far);

	if (!hit) {
		discard;
	} else {
		t_near = max(t_near, 0.0);

		// 품질 모드에 따른 레이마칭 스텝 수 동적 결정
		int active_msteps = march_steps;
		int active_lsteps = light_steps;
		if (quality_mode == 3) {
			// 노트북 / 경량 모드: 5스텝 레이마칭, 광원 마칭 비활성화(초고속)
			active_msteps = 5;
			active_lsteps = 0;
		} else if (quality_mode == 2) {
			// 보통 모드: 10스텝, 단일 광원 샘플링
			active_msteps = 10;
			active_lsteps = 1;
		} else if (quality_mode == 0) {
			// 울트라 모드: 28스텝 고정밀
			active_msteps = 28;
			active_lsteps = 3;
		}

		float wind_time  = TIME * time_speed;
		vec3  light_obj  = -v_sun_obj;
		float step_size  = (t_far - t_near) / float(active_msteps);
		vec3  cur_pos    = ro + rd * (t_near + step_size * 0.5);
		float cos_theta  = dot(rd, v_sun_obj);
		float phase      = hg_phase(cos_theta, forward_scatter);

		float transmittance = 1.0;
		vec3  radiance      = vec3(0.0);

		for (int i = 0; i < active_msteps; i++) {
			float d = sample_density(cur_pos, wind_time);

			if (d > 0.001) {
				float vert_t   = clamp(cur_pos.y + 0.5, 0.0, 1.0);
				vec3  base_col = mix(cloud_bottom_color.rgb, cloud_top_color.rgb, vert_t);
				vec3  shad_col = cloud_shadow_color.rgb;

				float sun_atten = (active_lsteps > 0) ? light_march(cur_pos, light_obj, wind_time, active_lsteps) : 0.85;
				vec3  sample_col = mix(shad_col, base_col, sun_atten);
				float extinction = d * step_size;

				float night_dim := mix(1.0, 0.38, night_weight);
				float ambient_now := mix(ambient_light, ambient_light * 0.24, night_weight);
				radiance      += transmittance * (sample_col * d * phase * sun_atten + ambient_now * d * base_col) * step_size * night_dim * moonlight_scale;
				transmittance *= exp(-extinction);

				if (transmittance < 0.03) {
					break;
				}
			}

			cur_pos += rd * step_size;
		}

		float alpha = clamp(1.0 - transmittance, 0.0, 1.0);

		if (alpha < 0.015) {
			discard;
		} else {
			ALBEDO = clamp(radiance, vec3(0.0), vec3(1.0)) / max(alpha, 0.01);
			ALPHA  = alpha;
		}
	}
}
