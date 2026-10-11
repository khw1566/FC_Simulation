uniform vec2 sun_uv = vec2(-10.0);
uniform float flare_visibility = 0.0;
uniform float flare_strength = 0.34;

vec3 lens_flare(vec2 uv, vec2 pixel) {
	if (flare_visibility <= 0.001) { return vec3(0.0); }
	vec2 aspect = vec2(pixel.y / pixel.x, 1.0);
	vec2 p = (uv - sun_uv) * aspect;
	float r = length(p);
	float halo = exp(-r * 22.0) * 0.32;
	float streak = exp(-abs(p.y) * 420.0 - abs(p.x) * 10.0) * 0.18;
	vec3 color = vec3(1.0, 0.76, 0.44) * (halo + streak);
	vec2 axis = vec2(0.5) - sun_uv;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 q = (uv - (sun_uv + axis * (0.75 + fi * 0.48))) * aspect;
		float radius = 0.023 + fi * 0.012;
		float ghost = exp(-pow(length(q) / radius, 4.0)) * 0.035;
		color += mix(vec3(0.3, 0.65, 1.0), vec3(1.0, 0.42, 0.19), fi / 3.0) * ghost;
	}
	if (max(max(color.r, color.g), color.b) < 0.00005) { return vec3(0.0); }
	return color * flare_strength;
}
