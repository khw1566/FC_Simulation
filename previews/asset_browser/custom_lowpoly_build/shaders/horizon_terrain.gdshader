shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D regional_height_texture : filter_linear, repeat_disable;
uniform sampler2D splatmap_texture : filter_linear, repeat_disable;
uniform bool has_splatmap = false;
uniform bool simple_contour_mode = false;
uniform bool flat_map = false;
uniform float world_size_meters = 80000.0;
uniform vec4 map_bbox; // west, south, east, north
uniform vec4 regional_bbox;
uniform vec3 grass_color : source_color = vec3(0.24,0.38,0.18);
uniform vec3 rock_color : source_color = vec3(0.40,0.38,0.35);
uniform vec3 snow_color : source_color = vec3(0.85,0.88,0.90);
uniform vec3 dry_sand_color : source_color = vec3(0.76,0.72,0.54);
uniform vec3 wet_sand_color : source_color = vec3(0.48,0.44,0.35);
uniform vec3 coastal_cliff_color : source_color = vec3(0.30,0.30,0.32);
uniform vec3 forest_tone : source_color = vec3(0.18,0.32,0.16);
uniform vec3 farmland_tone : source_color = vec3(0.42,0.46,0.28);
uniform vec3 urban_tone : source_color = vec3(0.38,0.40,0.42);
uniform vec3 water_albedo : source_color = vec3(0.035,0.16,0.25);
uniform vec3 shallow_water_color : source_color = vec3(0.10,0.29,0.34);
uniform vec3 simple_land_color : source_color = vec3(0.82,0.84,0.85);
uniform vec3 simple_water_color : source_color = vec3(0.20,0.28,0.35);
varying vec3 world_position;
varying vec3 world_normal;
float mercator(float latitude) { return log(tan(0.7853981634+radians(clamp(latitude,-85.0,85.0))*0.5)); }
void vertex() {
    world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
}
void fragment() {
    vec2 local_uv = world_position.xz/world_size_meters+0.5;
    float longitude = mix(map_bbox.x,map_bbox.z,local_uv.x);
    float latitude = mix(map_bbox.w,map_bbox.y,local_uv.y);
    vec2 uv = vec2((longitude-regional_bbox.x)/(regional_bbox.z-regional_bbox.x),
        (mercator(regional_bbox.w)-mercator(latitude))/(mercator(regional_bbox.w)-mercator(regional_bbox.y)));
    vec3 encoded = texture(regional_height_texture,uv).rgb;
    float elevation = encoded.r*65280.0+encoded.g*255.0-32768.0;
    bool outside = any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)));
    float edge_distance = max(max(abs(world_position.x),abs(world_position.z))-world_size_meters*0.5,0.0);
    float h = mix(COLOR.r*10000.0,elevation,smoothstep(0.0,6000.0,edge_distance));
    float water = outside ? 1.0 : 1.0-smoothstep(0.0,1.0,h);
    if (flat_map) { h = COLOR.r*10000.0; water = 0.0; }
    vec3 col;
    if (simple_contour_mode) {
        col = mix(simple_land_color,simple_water_color,water);
    } else {
        col = h<250.0 ? mix(grass_color,rock_color,clamp((h-12.0)/238.0,0.0,1.0))
                     : mix(rock_color,snow_color,clamp((h-250.0)/500.0,0.0,1.0));
        if (h<12.0) { col = mix(dry_sand_color,grass_color,clamp((h-2.5)/9.5,0.0,1.0)); }
        if (h<2.5) { col = mix(wet_sand_color,dry_sand_color,clamp((h-0.6)/1.9,0.0,1.0)); }
        if (h<0.6) { col = mix(coastal_cliff_color,wet_sand_color,clamp(h/0.6,0.0,1.0)); }
        vec4 splat = has_splatmap ? texture(splatmap_texture,clamp(local_uv,vec2(0.0),vec2(1.0))) : vec4(0.0);
        // 피복 표본이 없는 원경은 같은 숲·암석 팔레트로 연결하며 도시 배치를 추정하지 않는다.
        splat = mix(splat,vec4(0.8,0.0,0.0,0.0),smoothstep(0.0,18000.0,edge_distance));
        col = mix(col,forest_tone,splat.r*0.75);
        col = mix(col,farmland_tone,splat.g*0.85);
        col = mix(col,urban_tone,splat.b*0.80);
        float slope = 1.0-max(world_normal.y,0.0);
        col = mix(col,rock_color,smoothstep(0.18,0.45,slope));
        vec3 sea = mix(water_albedo,shallow_water_color,smoothstep(-20.0,0.0,h)*0.15);
        col = mix(col,sea,water);
    }
    // 물결은 해상도보다 작아지면 억제하여 고고도 반짝임을 막는다.
    float wave_weight = 1.0-smoothstep(1000.0,10000.0,distance(CAMERA_POSITION_WORLD,world_position));
    float phase = TIME*0.35;
    vec2 p = world_position.xz*0.035;
    vec3 sea_normal = normalize(vec3(sin(p.x+phase)*cos(p.y*0.8+phase*0.7)*0.045,1.0,
        cos(p.x*1.6-phase*0.6)*sin(p.y*1.3+phase)*0.045));
    NORMAL = normalize((VIEW_MATRIX*vec4(normalize(mix(world_normal,sea_normal,water*wave_weight)),0.0)).xyz);
    ALBEDO = col;
    float far_water = smoothstep(10000.0,20000.0,distance(CAMERA_POSITION_WORLD,world_position));
    ROUGHNESS = mix(0.88,mix(0.30,0.55,far_water),water);
    SPECULAR = mix(0.1,mix(0.35,0.12,far_water),water);
}
