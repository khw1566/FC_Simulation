shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
uniform vec4 light_color : source_color = vec4(1.0);
uniform bool directional = false;
varying vec3 lamp_position;
varying vec3 lamp_facing;

void vertex() {
	lamp_position = MODEL_MATRIX[3].xyz;
	lamp_facing = normalize(MODEL_MATRIX[2].xyz);
	float distance_m = length((VIEW_MATRIX * vec4(lamp_position, 1.0)).xyz);
	float size = clamp(distance_m * 0.006, 1.2, 18.0);
	MODELVIEW_MATRIX = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * MODELVIEW_MATRIX;
	VERTEX.xy *= size;
}

void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float facing = dot(normalize(CAMERA_POSITION_WORLD - lamp_position), lamp_facing);
	float visibility = directional ? smoothstep(0.0, 0.12, facing) : 1.0;
	ALBEDO = light_color.rgb * 3.0;
	ALPHA = smoothstep(1.0, 0.05, radius) * visibility;
}
