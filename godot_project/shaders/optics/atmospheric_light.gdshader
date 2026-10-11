shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#include "cloud_field.gdshaderinc"
#include "optical_depth.gdshaderinc"
#include "cloud_transmission.gdshaderinc"
#include "lens_flare.gdshaderinc"
uniform vec3 sun_color = vec3(1.0);
uniform float haze_density = 0.000028;
uniform float ray_strength = 0.75;
uniform int ray_steps = 6;
uniform float ray_distance = 10000.0;

void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }

void fragment() {
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec3 view_ray = normalize(optical_view(SCREEN_UV, 0.5, INV_PROJECTION_MATRIX));
	vec3 ray = normalize((INV_VIEW_MATRIX * vec4(view_ray, 0.0)).xyz);
	float limit = optical_sky(depth) ? ray_distance : min(length(optical_view(SCREEN_UV, depth, INV_PROJECTION_MATRIX)), ray_distance);
	if (ray.y > 0.001 && camera.y < slab_bottom && clouds_active) {
		limit = min(limit, (slab_bottom - camera.y) / ray.y);
	}
	float daylight = smoothstep(0.015, 0.18, sun_direction.y);
	vec3 color = vec3(0.0);
	if (haze_density > 0.0 && clouds_active && daylight > 0.0 && ray_strength > 0.0) {
		float ds = limit / float(ray_steps);
		float scatter = 0.0;
		// 고정 중점 표본으로 시간 노이즈에 의한 깜박임을 피한다.
		for (int i = 0; i < ray_steps; i++) {
			float distance = (float(i) + 0.5) * ds;
			vec3 p = camera + ray * distance;
			float density = haze_density * exp(-max(p.y, 0.0) / 8000.0);
			scatter += cloud_transmission(p) * density * ds * exp(-distance * haze_density);
		}
		float mu = max(dot(ray, sun_direction), 0.0);
		float phase = 0.08 + 0.32 * pow(mu, 6.0) + 0.6 * pow(mu, 32.0);
		color = sun_color * scatter * phase * ray_strength * daylight;
	}
	vec2 pixel = 1.0 / VIEWPORT_SIZE.xy;
	vec3 flare = lens_flare(SCREEN_UV, pixel);
	if (max(max(flare.r, flare.g), flare.b) > 0.00001) {
		float visibility = 0.0;
		// Compatibility의 깊이 버퍼는 fragment 범위에서 읽는다.
		for (int i = 0; i < 5; i++) {
			float a = float(i) * 6.2831853 / 5.0;
			vec2 uv = sun_uv + vec2(cos(a), sin(a)) * pixel * 2.0;
			visibility += optical_sky(texture(scene_depth, clamp(uv, vec2(0.0), vec2(1.0))).r) ? 0.2 : 0.0;
		}
		color += flare * visibility * flare_visibility * cloud_transmission(camera) * sun_color;
	}
	ALBEDO = color;
	ALPHA = 1.0;
}
