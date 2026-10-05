shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

float foam_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 weight = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	float a = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(cell + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(cell + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(cell + vec2(1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, weight.x), mix(c, d, weight.x), weight.y);
}

void fragment() {
	float lateral = abs(UV.x * 2.0 - 1.0);
	float edge = 1.0 - smoothstep(0.72, 1.0, lateral);
	float bubbles = foam_noise(vec2(UV.x * 22.0, UV.y * 5.0) + vec2(TIME * 0.25, TIME * 0.16));
	float ripple = 0.65 + 0.35 * sin(UV.y * 13.0 + lateral * 24.0 - TIME * 2.2);
	ALBEDO = vec3(0.92, 0.97, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = COLOR.a * edge * smoothstep(0.22, 0.7, bubbles) * ripple * 0.85;
}
