shader_type spatial;
// 충격파 뒤 감압 구간에서 습기가 순간 응결해 생기는 윌슨 구름(반구 껍질).
// 시선이 껍질을 비스듬히 지날수록 짙고, 습윤층 단차를 따라 고도별 띠가 생긴다.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler3D shape_noise : repeat_enable, filter_linear;
uniform vec3 shell_center = vec3(0.0);
uniform float shell_radius = 100.0;
uniform float ground_height = 0.0;
uniform float shell_alpha = 0.0;
uniform vec3 shell_color = vec3(0.92, 0.94, 0.97);
uniform float anim_time = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (world_pos.y < ground_height || shell_alpha < 0.002) { discard; }
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
	float rim = pow(1.0 - abs(dot(world_normal, view)), 2.0);
	vec3 q = (world_pos - shell_center) / (shell_radius * 0.35);
	float n = texture(shape_noise, q + vec3(0.0, anim_time * 0.05, 0.0)).r;
	float h = (world_pos.y - ground_height) / shell_radius;
	float bands = 0.55 + 0.45 * sin(h * 9.0 + n * 3.0);
	float a = shell_alpha * (0.1 + 0.9 * rim) * smoothstep(0.32, 0.68, n) * bands;
	a *= smoothstep(0.0, 0.04, h);
	ALBEDO = shell_color;
	ALPHA = clamp(a, 0.0, 0.9);
}
