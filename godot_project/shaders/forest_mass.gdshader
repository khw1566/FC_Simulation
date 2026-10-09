shader_type spatial;
render_mode cull_disabled;

// 숲 수관 덩어리. 카메라 거리 fade_near_m ~ fade_near_m + fade_band_m 구간에서 디더로 나타나고
// 그보다 가까우면 그리지 않는다. 같은 구간에서 개별 수목(vegetation_sway.gdshader)이 사라진다.

uniform sampler2D canopy_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform float fade_near_m = 100.0;
uniform float fade_band_m = 20.0;

varying vec3 v_world;

float bayer4(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int index = x + y * 4;
	float pattern[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (pattern[index] + 0.5) / 16.0;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(CAMERA_POSITION_WORLD - v_world);
	float show = smoothstep(fade_near_m, fade_near_m + fade_band_m, d);
	// 개체 쪽 디더 패턴과 상보적으로 써서 전환 구간에서도 같은 픽셀을 둘이 함께 그리지 않는다.
	if (show <= 1.0 - bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 base = has_texture ? texture(canopy_texture, UV).rgb : vec3(1.0);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
