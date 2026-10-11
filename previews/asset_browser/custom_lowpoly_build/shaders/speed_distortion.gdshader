shader_type canvas_item;

// 가속 시 고속 주행 방사형 블러 및 배럴 왜곡
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	if (distortion_strength <= 0.001) {
		COLOR = texture(screen_texture, SCREEN_UV);
	} else {
		vec2 center = vec2(0.5, 0.5);
		vec2 dir = SCREEN_UV - center;
		float dist = length(dir);

		// 배럴 렌즈 왜곡 (어안 렌즈 효과)
		vec2 distorted_uv = center + dir * (1.0 + distortion_strength * 0.25 * dist * dist);

		// 방사형 다중 샘플링 (Speed Radial Blur)
		vec4 sum = vec4(0.0);
		float samples = 6.0;
		for (float i = 0.0; i < 6.0; i += 1.0) {
			float scale = 1.0 - (i / samples) * distortion_strength * 0.08 * dist;
			vec2 sample_uv = center + (distorted_uv - center) * scale;
			sum += texture(screen_texture, sample_uv);
		}
		vec4 col = sum / samples;

		// 고속 이동 시 주변부 비네팅(Vignette) 효과
		float vignette = 1.0 - smoothstep(0.4, 0.9, dist * (1.0 + distortion_strength * 0.5));
		col.rgb = mix(col.rgb * 0.7, col.rgb, vignette);

		COLOR = col;
	}
}
