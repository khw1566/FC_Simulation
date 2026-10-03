// 4회 선형 샘플로 양의 B-spline 보간. 음의 가중치가 없어 둑 밖 번짐을 억제한다.
float smooth_water_mask(sampler2D mask_texture, vec2 uv) {
	vec2 size = vec2(textureSize(mask_texture, 0));
	vec2 p = uv * size - 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 a = (cell - 0.5 + w1 / g0) / size;
	vec2 b = (cell + 1.5 + w3 / g1) / size;
	float near_mask = mix(
		mix(textureLod(mask_texture, vec2(a.x, a.y), 0.0).r, textureLod(mask_texture, vec2(b.x, a.y), 0.0).r, g1.x),
		mix(textureLod(mask_texture, vec2(a.x, b.y), 0.0).r, textureLod(mask_texture, vec2(b.x, b.y), 0.0).r, g1.x), g1.y);
	vec2 footprint = fwidth(uv) * size;
	float distant = smoothstep(0.75, 2.0, max(footprint.x, footprint.y));
	return mix(near_mask, texture(mask_texture, uv).r, distant);
}
