shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec3 bed_world;

float grain(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    float a = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
    float b = fract(sin(dot(cell+vec2(1.0,0.0), vec2(127.1, 311.7))) * 43758.5453);
    float c = fract(sin(dot(cell+vec2(0.0,1.0), vec2(127.1, 311.7))) * 43758.5453);
    float d = fract(sin(dot(cell+vec2(1.0), vec2(127.1, 311.7))) * 43758.5453);
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

void vertex() {
    bed_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float grains = grain(bed_world.xz * 3.8);
    float patches = 0.5 + 0.5 * sin(bed_world.x * 0.12 + sin(bed_world.z * 0.10));
    vec3 gravel = mix(vec3(0.25, 0.25, 0.21), vec3(0.42, 0.39, 0.30), patches);
    ALBEDO = gravel * mix(0.90, 1.06, grains);
    ROUGHNESS = 0.95;
    SPECULAR = 0.12;
}
