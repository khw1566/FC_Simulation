shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.22,0.34,0.14,1.0);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p = world_position.xz;
    float broad = sin(p.x * 0.43 + sin(p.y * 0.27)) * sin(p.y * 0.37);
    float grain = fract(sin(dot(floor(p * 8.0), vec2(12.9898,78.233))) * 43758.5453);
    ALBEDO = base_color.rgb * (0.94 + broad * 0.07 + grain * 0.08);
    ROUGHNESS = 1.0;
}
