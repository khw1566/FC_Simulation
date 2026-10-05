shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.2, 1.0, length(p));
	float wisps = 0.78 + 0.22 * sin(p.x * 8.0 + sin(p.y * 6.0) + TIME * 0.35);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * edge * wisps;
}
