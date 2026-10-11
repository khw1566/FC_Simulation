shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 지형 관리자가 높이맵을 넘기기 전에는 해양 마스크(0.5 경계)로, 넘긴 뒤에는 전체 수계 마스크와
// 지형 높이로 그린다. 후자에서 해안선은 마스크 경계가 아니라 지형이 해수면과 만나는 선(깊이 판정)이 된다.
uniform sampler2D water_mask_texture : filter_linear, repeat_disable;
uniform bool has_water_mask = false;
uniform sampler2D terrain_height_texture : filter_linear, repeat_disable;
uniform bool has_terrain_height = false;
// 렌더링 전용 수계 거리장. 있으면 마스크 대신 이것으로 수계 허용 영역과 얕은물 띠를 정한다.
uniform sampler2D water_sdf_texture : filter_linear, repeat_disable;
uniform bool has_water_sdf = false;
uniform float terrain_min_height = 0.0;
uniform float terrain_max_height = 1.0;
uniform float sea_level_y = 0.0;
uniform float world_size_meters = 28000.0;
varying vec3 water_world_position;
uniform bool has_river_overlay = false;
uniform sampler2D river_overlay_mask : filter_nearest, repeat_disable;
uniform vec4 river_overlay_rect = vec4(0.0, 0.0, 1.0, 1.0);

#include "res://shaders/water_mask_filter.gdshaderinc"
#include "res://shaders/water_surface.gdshaderinc"

void vertex() {
    water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    if (has_river_overlay) {
        vec2 river_uv = (water_world_position.xz - river_overlay_rect.xy) / river_overlay_rect.zw;
        if (all(greaterThanEqual(river_uv, vec2(0.0))) && all(lessThanEqual(river_uv, vec2(1.0)))) {
            if (texture(river_overlay_mask, river_uv).r > 0.5) { discard; }
        }
    }
    vec2 map_uv = water_world_position.xz / world_size_meters + vec2(0.5);
    bool in_map = all(greaterThanEqual(map_uv, vec2(0.0))) && all(lessThanEqual(map_uv, vec2(1.0)));
    // 맵 밖 해수면은 곡률을 적용한 광역 원경이 담당한다.
    if (!in_map) { discard; }
    float coverage = 1.0;
    float depth_m = 30.0;
    if (has_water_sdf && has_terrain_height) {
        float distance_m = decode_water_sdf(texture(water_sdf_texture, map_uv).r);
        // 지형 셰이더의 제거 기준보다 0.5m 넓게 그려 지형이 걷힌 곳에 틈이 생기지 않게 한다.
        if (distance_m > WATER_SDF_ZONE_M + 0.5) { discard; }
        coverage = water_sdf_shading_coverage(distance_m);
        float bed_y = mix(terrain_min_height, terrain_max_height, texture(terrain_height_texture, map_uv).r);
        depth_m = max(sea_level_y - bed_y, 0.0);
    } else if (has_water_mask && has_terrain_height) {
        coverage = smooth_water_mask(water_mask_texture, map_uv);
        // 수계 바깥 저지대만 막는다. 수계 안쪽 해안선은 지형과의 깊이 판정이 정한다.
        if (coverage < 0.02) { discard; }
        float bed_y = mix(terrain_min_height, terrain_max_height, texture(terrain_height_texture, map_uv).r);
        depth_m = max(sea_level_y - bed_y, 0.0);
    } else if (has_water_mask) {
        coverage = texture(water_mask_texture, map_uv).r;
        if (coverage < 0.5) { discard; }
    }
    float view_distance = distance(CAMERA_POSITION_WORLD, water_world_position);
    vec3 world_normal = water_surface_normal(water_world_position.xz, TIME, view_distance);
    NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
    ALBEDO = water_surface_color(coverage, depth_m, water_world_position.xz, TIME);
    ROUGHNESS = water_surface_roughness(coverage, view_distance);
    SPECULAR = water_surface_specular(view_distance);
}
