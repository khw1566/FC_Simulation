shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_albedo : source_color = vec4(0.035, 0.16, 0.25, 1.0);
uniform vec4 shallow_water_color : source_color = vec4(0.10, 0.29, 0.34, 1.0);
uniform sampler2D water_mask_texture : filter_linear, repeat_disable;
uniform bool has_water_mask = false;
uniform float world_size_meters = 28000.0;
uniform float wave_speed = 0.35;
uniform float wave_strength = 0.045;
varying vec3 water_world_position;

void vertex() {
    water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 map_uv = water_world_position.xz / world_size_meters + vec2(0.5);
    float coverage = 1.0;
    bool in_map = all(greaterThanEqual(map_uv, vec2(0.0))) && all(lessThanEqual(map_uv, vec2(1.0)));
    // 맵 밖 해수면은 곡률을 적용한 광역 원경이 담당한다.
    if (!in_map) { discard; }
    if (has_water_mask && in_map) {
        coverage = texture(water_mask_texture, map_uv).r;
        if (coverage < 0.5) { discard; }
    }
    // 월드 미터 단위 물결로 맵 크기에 따른 파장 변화를 방지한다.
    vec2 p = water_world_position.xz * 0.035;
    float phase = TIME * wave_speed;
    float a = sin(p.x + phase) * cos(p.y * 0.8 + phase * 0.7);
    float b = cos(p.x * 1.6 - phase * 0.6) * sin(p.y * 1.3 + phase);
    float view_distance = distance(CAMERA_POSITION_WORLD,water_world_position);
    float wave_weight = 1.0-smoothstep(1000.0,10000.0,view_distance);
    vec3 world_normal = normalize(vec3(a * wave_strength * wave_weight, 1.0, b * wave_strength * wave_weight));
    NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
    float shore = has_water_mask && in_map ? 1.0 - smoothstep(0.5, 0.95, coverage) : 0.0;
    vec3 color = mix(water_albedo.rgb, shallow_water_color.rgb, shore);
    float foam = shore * (0.5 + 0.5 * sin(p.x * 0.6 + p.y + phase));
    ALBEDO = mix(color, vec3(0.66, 0.77, 0.78), foam * 0.18);
    float far_water = smoothstep(10000.0,20000.0,view_distance);
    ROUGHNESS = mix(mix(0.30, 0.46, shore),0.55,far_water);
    SPECULAR = mix(0.35,0.12,far_water);
}
