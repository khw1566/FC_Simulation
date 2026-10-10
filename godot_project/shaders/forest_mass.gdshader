shader_type spatial;
render_mode cull_disabled;

// 숲 수관 덩어리. 카메라 거리 fade_near_m ~ fade_near_m + fade_band_m 구간에서 디더로 나타나고
// 그보다 가까우면 그리지 않는다. 같은 구간에서 개별 수목(vegetation_sway.gdshader)이 사라진다.

uniform sampler2D canopy_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform float fade_near_m = 100.0;
uniform float fade_band_m = 20.0;
// 원경 단색: flat_near_m~flat_far_m 구간에서 잎 무늬를 가장 작은 밉맵(평균색)과 완만한 그라데이션으로 바꾼다.
uniform float flat_near_m = 200.0;
uniform float flat_far_m = 550.0;
uniform float gradient_strength = 0.10;

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
	float flat_mix = has_texture ? smoothstep(flat_near_m, flat_far_m, d) : 0.0;
	float gradient = sin(v_world.x * 0.0047 + 1.3) * sin(v_world.z * 0.0039 - 0.7) * 0.6 + sin((v_world.x + v_world.z) * 0.0017) * 0.4;
	vec3 flat_color = (has_texture ? textureLod(canopy_texture, vec2(0.5), 12.0).rgb : vec3(1.0)) * (1.0 + gradient * gradient_strength);
	vec3 base = has_texture ? mix(texture(canopy_texture, UV).rgb, flat_color, flat_mix) : vec3(1.0);
	// 원경에서는 정점 색 얼룩도 줄여 덩어리가 단색에 가깝게 보이게 한다(가장자리 음영은 일부 유지).
	ALBEDO = base * mix(COLOR.rgb, vec3(0.9), flat_mix * 0.7);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
