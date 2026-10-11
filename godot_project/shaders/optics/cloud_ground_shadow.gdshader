shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#include "cloud_field.gdshaderinc"
#include "optical_depth.gdshaderinc"
#include "cloud_transmission.gdshaderinc"
uniform float shadow_strength = 0.32;
uniform float haze_density = 0.000028;

void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
	if (optical_sky(depth)) { discard; }
	vec3 view = optical_view(SCREEN_UV, depth, INV_PROJECTION_MATRIX);
	vec3 world = (INV_VIEW_MATRIX * vec4(view, 1.0)).xyz;
	float light = cloud_transmission(world);
	float fade = exp(-length(view) * haze_density);
	float daylight = smoothstep(0.015, 0.18, sun_direction.y);
	ALBEDO = vec3(1.0 - (1.0 - light) * shadow_strength * fade * daylight);
	ALPHA = 1.0;
}
