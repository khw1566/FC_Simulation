shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 3D 구름 셰이더 (절차적 노이즈 및 림 라이팅 기반)
uniform vec4 cloud_color : source_color = vec4(0.92, 0.94, 0.97, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.48, 0.52, 0.60, 1.0);
uniform float noise_scale : hint_range(0.01, 2.0) = 0.15;
uniform float time_speed : hint_range(0.0, 1.0) = 0.05;
uniform float displacement_strength : hint_range(0.0, 30.0) = 12.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.8;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.15;

// 해시 기반 3D 심플렉스/퍼린형 노이즈
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 p = floor(x);
	vec3 w = fract(x);
	vec3 u = w * w * (3.0 - 2.0 * w);

	float n = p.x + p.y * 157.0 + 113.0 * p.z;
	return mix(
		mix(mix(hash(p + vec3(0,0,0)), hash(p + vec3(1,0,0)), u.x),
			mix(hash(p + vec3(0,1,0)), hash(p + vec3(1,1,0)), u.x), u.y),
		mix(mix(hash(p + vec3(0,0,1)), hash(p + vec3(1,0,1)), u.x),
			mix(hash(p + vec3(0,1,1)), hash(p + vec3(1,1,1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float f = 0.0;
	f += 0.5000 * noise(p); p *= 2.02;
	f += 0.2500 * noise(p); p *= 2.03;
	f += 0.1250 * noise(p); p *= 2.01;
	return f;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wind_offset = vec3(TIME * time_speed * 10.0, 0.0, TIME * time_speed * 5.0);
	float n = fbm((world_pos + wind_offset) * noise_scale);
	
	// 정점 변위를 통해 부피감 있고 울퉁불퉁한 구름 표면 형성
	VERTEX += NORMAL * (n - 0.4) * displacement_strength;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wind_offset = vec3(TIME * time_speed * 10.0, 0.0, TIME * time_speed * 5.0);
	float n = fbm((world_pos + wind_offset) * (noise_scale * 1.5));

	// 상단/하단 명암 그라데이션 (태양광 산란 모방)
	float vertical_shade = clamp((NORMAL.y + 0.3) * 0.8, 0.0, 1.0);
	vec3 col = mix(shadow_color.rgb, cloud_color.rgb, vertical_shade);

	// 림 라이팅 (가장자리 투광 효과)
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col += cloud_color.rgb * pow(rim, 2.5) * rim_strength;

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
	
	// 외곽 부드러운 투과도
	float alpha = smoothstep(alpha_cutoff, 1.0, n * 1.2);
	ALPHA = clamp(alpha * 0.95, 0.0, 1.0);
}
