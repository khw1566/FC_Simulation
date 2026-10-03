shader_type spatial;
// 출구 면만 적분해 내부 진입을 지원하고 중복 그리기를 줄인다.
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_front, unshaded;
uniform sampler3D shape_noise : repeat_enable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform int quality_mode = 1;
// 전처리기 대신 생성 시 실제 렌더러의 깊이 좌표 규약을 전달한다.
uniform bool compatibility_depth = false;
uniform int cloud_type = 0;
uniform float opacity = 0.0;
uniform float night_weight : hint_range(0.0, 1.0) = 0.0;
uniform float moonlight_scale : hint_range(0.0, 1.0) = 1.0;
uniform float coverage = 0.6;
uniform float cloud_density = 8.0;
uniform vec3 noise_offset = vec3(0.0);
uniform vec4 cloud_top_color : source_color = vec4(0.96, 0.97, 1.0, 1.0);
uniform vec4 cloud_bottom_color : source_color = vec4(0.60, 0.65, 0.73, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.30, 0.32, 0.38, 1.0);
uniform vec3 player_pos_obj = vec3(999.0);
uniform float player_wake_strength = 0.0;
varying vec3 camera_local;
varying vec3 vertex_local;
varying mat4 world_to_local;
float dome(vec3 p, vec3 center, vec3 radii) {
	return 1.0 - smoothstep(0.65, 1.0, length((p - center) / radii));
}
float density_at(vec3 p) {
	float edge = 1.0 - smoothstep(0.38, 0.49, max(abs(p.x), abs(p.z)));
	float height = smoothstep(-0.46, -0.32, p.y) * (1.0 - smoothstep(0.30, 0.48, p.y));
	vec3 uv = p * 0.65 + noise_offset + vec3(TIME * 0.0015, 0.0, 0.0);
	float mask;
	float n;
	if (cloud_type == 1) {
		// 층운: 넓은 연속층과 낮은 기복.
		n = texture(shape_noise, uv * vec3(1.2, 0.18, 1.2)).r;
		mask = edge * height;
		n = smoothstep(0.20 + (1.0 - coverage) * 0.30, 0.70, n);
	} else if (cloud_type == 2) {
		// 권운: 바람 방향으로 늘어진 섬유와 굽은 꼬리.
		uv.z += sin(p.x * 7.0 + noise_offset.x * 5.0) * 0.075;
		n = texture(shape_noise, uv * vec3(0.28, 0.3, 4.5)).r;
		float strands = texture(shape_noise, uv * vec3(0.6, 0.3, 11.0)).r;
		n = smoothstep(0.42, 0.72, n * 0.7 + strands * 0.3);
		mask = edge * height;
	} else {
		// 적운: 평평한 밑면과 크기가 다른 응결 덩어리.
		mask = max(dome(p, vec3(-0.16, -0.12, 0.0), vec3(0.30, 0.30, 0.34)), dome(p, vec3(0.12, 0.02, 0.06), vec3(0.28, 0.43, 0.30)));
		mask = max(mask, dome(p, vec3(0.0, -0.12, -0.19), vec3(0.30, 0.26, 0.23)));
		mask = max(mask, dome(p, vec3(0.26, -0.20, -0.06), vec3(0.20, 0.20, 0.27)));
		if (cloud_type == 3) {
			mask = max(mask, dome(p, vec3(0.0, 0.28, 0.0), vec3(0.47, 0.16, 0.45)));
		}
		mask *= height * edge;
		n = texture(shape_noise, uv * 1.4).r;
		if (quality_mode < 2) { n = n * 0.8 + texture(shape_noise, uv * 4.2).r * 0.2; }
		n = smoothstep(0.22 + (1.0 - coverage) * 0.25, 0.70, n);
	}
	float wake = 1.0 - player_wake_strength * (1.0 - smoothstep(0.04, 0.16, length(p - player_pos_obj)));
	return mask * n * cloud_density * wake;
}

void vertex() {
	world_to_local = inverse(MODEL_MATRIX);
	camera_local = (world_to_local * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vertex_local = VERTEX;
}
void fragment() {
	if (opacity < 0.001) { discard; }
	vec3 ray = normalize(vertex_local - camera_local);
	vec3 safe_ray = mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), ray)) * max(abs(ray), vec3(0.000001));
	vec3 t0 = (-vec3(0.5) - camera_local) / safe_ray;
	vec3 t1 = (vec3(0.5) - camera_local) / safe_ray;
	vec3 near3 = min(t0, t1);
	vec3 far3 = max(t0, t1);
	float begin = max(0.0, max(near3.x, max(near3.y, near3.z)));
	float end = min(far3.x, min(far3.y, far3.z));
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	if (compatibility_depth) {
		ndc.z = depth * 2.0 - 1.0;
	}
	vec4 view_point = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	if (abs(view_point.w) > 0.000001) {
		vec4 world_point = INV_VIEW_MATRIX * vec4(view_point.xyz / view_point.w, 1.0);
		vec3 opaque_local = (world_to_local * world_point).xyz;
		end = min(end, dot(opaque_local - camera_local, ray));
	}
	if (end <= begin) { discard; }
	int steps = 12;
	if (quality_mode == 0) { steps = 18; }
	if (quality_mode == 2) { steps = 8; }
	if (quality_mode >= 3) { steps = 5; }
	if (cloud_type == 2) { steps = min(steps, 6); }
	float stride = (end - begin) / float(steps);
	float transmission = 1.0;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 18; i++) {
		if (i >= steps) { break; }
		vec3 p = camera_local + ray * (begin + (float(i) + 0.5) * stride);
		float alpha = 1.0 - exp(-density_at(p) * stride);
		float light = smoothstep(-0.40, 0.40, p.y);
		vec3 color = mix(cloud_bottom_color.rgb, cloud_top_color.rgb, light);
		color = mix(color, cloud_shadow_color.rgb, (1.0 - light) * 0.22);
		color *= mix(1.0, 0.46, night_weight);
		sum += transmission * alpha * color;
		transmission *= 1.0 - alpha;
		if (transmission < 0.025) { break; }
	}
	float alpha = 1.0 - transmission;
	ALBEDO = sum / max(alpha, 0.0001) * moonlight_scale;
	ALPHA = alpha * opacity;
}

