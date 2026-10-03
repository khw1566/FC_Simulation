shader_type sky;

const int MAX_STARS = 72;

uniform vec3 sky_top_color : source_color = vec3(0.32, 0.52, 0.78);
uniform vec3 sky_horizon_color : source_color = vec3(0.68, 0.75, 0.82);
uniform vec3 ground_color : source_color = vec3(0.12, 0.15, 0.18);
uniform float night_weight : hint_range(0.0, 1.0) = 0.0;
uniform vec3 star_directions[MAX_STARS];
uniform vec4 star_colors[MAX_STARS];
uniform float star_radii[MAX_STARS];
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float moon_radius = 0.0048;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float sun_radius = 0.00465;
uniform vec3 venus_direction = vec3(0.0, 1.0, 0.0);
uniform float venus_radius = 0.0016;

void sky() {
	vec3 ray = normalize(EYEDIR);
	float elevation = clamp(ray.y, -1.0, 1.0);
	float sky_blend = smoothstep(-0.03, 0.72, elevation);
	vec3 night_top = vec3(0.003, 0.006, 0.018);
	vec3 night_horizon = vec3(0.018, 0.026, 0.052);
	vec3 day_color = mix(sky_horizon_color, sky_top_color, sky_blend);
	vec3 night_color = mix(night_horizon, night_top, sky_blend);
	vec3 color = mix(day_color, night_color, night_weight);
	float horizon_mask = smoothstep(-0.002, 0.002, ray.y);
	float sun_angle = atan(length(cross(ray, sun_direction)), dot(ray, sun_direction));
	float sun_edge = max(fwidth(sun_angle), 0.0001);
	float sun_disk = 1.0 - smoothstep(sun_radius - sun_edge, sun_radius + sun_edge, sun_angle);
	color += vec3(1.0, 0.91, 0.72) * sun_disk * 6.0 * horizon_mask;
	if (elevation < 0.0) {
		float ground_blend = smoothstep(-0.24, -0.015, elevation);
		color = mix(ground_color, color, ground_blend);
	}
	float moon_angle = atan(length(cross(ray, moon_direction)), dot(ray, moon_direction));
	float moon_edge = max(fwidth(moon_angle) * 1.4, 0.00012);
	float moon_disk = 1.0 - smoothstep(moon_radius - moon_edge, moon_radius + moon_edge, moon_angle);
	vec3 moon_center = normalize(moon_direction);
	vec3 tangent = ray - moon_center * dot(ray, moon_center);
	vec3 disk_offset = tangent / max(sin(moon_radius), 0.0001);
	float depth = sqrt(max(0.0, 1.0 - dot(disk_offset, disk_offset)));
	vec3 moon_surface = (disk_offset - moon_center * depth) / max(length(disk_offset - moon_center * depth), 0.00001);
	float moon_lighting = max(dot(moon_surface, normalize(sun_direction)), 0.0);
	vec3 moon_color = vec3(0.80, 0.84, 0.91) * (moon_lighting * 1.8 + 0.025 * night_weight);
	color = mix(color, color * (1.0 - night_weight) + moon_color, moon_disk * horizon_mask);
	float venus_angle = acos(clamp(dot(ray, normalize(venus_direction)), -1.0, 1.0));
	float venus_disk = 1.0 - smoothstep(venus_radius * 0.55, venus_radius, venus_angle);
	float venus_above_horizon = smoothstep(-0.012, 0.012, venus_direction.y);
	color += vec3(1.0, 0.78, 0.48) * venus_disk * night_weight * venus_above_horizon * 1.6;
	for (int i = 0; i < MAX_STARS; i++) {
		if (star_directions[i].y > 0.0) {
			float star_angle = acos(clamp(dot(ray, normalize(star_directions[i])), -1.0, 1.0));
			float star_edge = max(fwidth(star_angle) * 1.2, 0.0001);
			float star_disk = 1.0 - smoothstep(star_radii[i] - star_edge, star_radii[i] + star_edge, star_angle);
			color += star_colors[i].rgb * star_disk * star_colors[i].a * night_weight * 1.65;
		}
	}
	COLOR = color;
}
