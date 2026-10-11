shader_type spatial;
render_mode cull_back;
uniform float wind_strength : hint_range(0.0,0.15) = 0.0;
uniform float lod_begin = 0.0;
uniform float lod_end = 100000.0;
varying flat float instance_distance;
void vertex() {
    vec3 instance_origin = (MODEL_MATRIX * vec4(0.0,0.0,0.0,1.0)).xyz;
    instance_distance = distance(instance_origin, CAMERA_POSITION_WORLD);
    float weight = clamp(VERTEX.y, 0.0, 1.0);
    VERTEX.x += sin(TIME * 1.3 + INSTANCE_CUSTOM.x * 6.283 + VERTEX.y * 2.0) * wind_strength * weight;
}
void fragment() {
    if (instance_distance < lod_begin || instance_distance >= lod_end) { discard; }
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 1.0;
}
