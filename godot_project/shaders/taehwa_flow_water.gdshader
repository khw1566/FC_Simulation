shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 실제 수심 대신 별도 하상과 깊이 버퍼를 이용한 시각화 광학이다.
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool compatibility_depth = true;
uniform float flow_speed_mps = 0.65;
uniform float simulation_time = -1.0;
uniform float absorption : hint_range(0.01, 2.0) = 0.36;
uniform float wave_strength : hint_range(0.0, 0.3) = 0.065;
uniform vec3 shallow_tint : source_color = vec3(0.14, 0.31, 0.27);
uniform vec3 deep_tint : source_color = vec3(0.035, 0.16, 0.17);
varying vec3 world_position;
varying vec3 local_up;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    local_up = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
    float time = simulation_time < 0.0 ? TIME : simulation_time;
    // UV.x는 하류로 증가하는 누적 거리, UV.y는 유향의 횡방향 거리다.
    float along = UV.x - time * flow_speed_mps;
    float wave_a = sin(along * 1.05 + sin(UV.y * 0.11) * 1.4);
    float wave_b = cos(along * 0.49 + UV.y * 1.63 - time * 0.18);
    float wave_c = sin(along * 2.07 - UV.y * 0.69);
    float fade = 1.0 - smoothstep(400.0, 4500.0, distance(CAMERA_POSITION_WORLD, world_position));
    vec2 direction = normalize(UV2 * 2.0 - 1.0 + vec2(0.00001));
    vec2 across = vec2(-direction.y, direction.x);
    vec2 slope = (direction * (wave_a + wave_c * 0.25) + across * wave_b * 0.65) * wave_strength * fade;
    vec3 normal_world = normalize(local_up + vec3(slope.x, 0.0, slope.y));
    vec3 normal_view = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
    NORMAL = normal_view;

    float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    float ndc_depth = compatibility_depth ? raw_depth * 2.0 - 1.0 : raw_depth;
    vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_depth, 1.0);
    float ray_depth = max(0.0, -behind.z / behind.w + VERTEX.z);
    float depth = min(COLOR.r * 8.0, ray_depth);
    float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(normal_view, normalize(VIEW)), 0.0, 1.0), 5.0);
    float transmittance = exp(-absorption * max(depth, 0.04));
    float shoreline = (1.0 - COLOR.g) * smoothstep(0.1, 0.8, depth);
    float turbulent = COLOR.b * (0.45 + 0.55 * sin(along * 2.4 + UV.y * 0.8) * sin(along * 1.3));
    float foam = clamp(shoreline * 0.10 + turbulent * 0.65, 0.0, 0.7);
    ALBEDO = mix(mix(deep_tint, shallow_tint, transmittance), vec3(0.72, 0.78, 0.73), foam);
    ALPHA = clamp(1.0 - transmittance + fresnel * 0.48 + foam * 0.5, 0.06, 0.94);
    ROUGHNESS = mix(0.13, 0.36, foam);
    SPECULAR = 0.5;
    METALLIC = 0.0;
}
