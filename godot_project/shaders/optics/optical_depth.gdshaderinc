uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool compatibility_depth = false;

bool optical_sky(float depth) {
	// Godot 4.3의 두 렌더러 모두 역방향 깊이: 먼 하늘은 0이다.
	return depth <= 0.000001;
}

vec3 optical_view(vec2 uv, float depth, mat4 inverse_projection) {
	float z = compatibility_depth ? depth * 2.0 - 1.0 : depth;
	vec4 p = inverse_projection * vec4(uv * 2.0 - 1.0, z, 1.0);
	return p.xyz / p.w;
}
