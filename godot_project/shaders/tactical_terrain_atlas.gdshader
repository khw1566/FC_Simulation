shader_type canvas_item;
uniform sampler2D sea_mask : filter_linear, repeat_disable;
uniform sampler2D river_mask : filter_linear, repeat_disable;
uniform float min_elevation = -50.0;
uniform float max_elevation = 750.0;
void fragment() {
    float h = mix(min_elevation, max_elevation, texture(TEXTURE, UV).r);
    float sea = texture(sea_mask, UV).r;
    float river = texture(river_mask, UV).r;
    float shade = clamp(0.91 - max(h, 0.0) * 0.00012, 0.72, 0.94);
    float contour = abs(fract(h / 25.0 - 0.5) - 0.5) * 25.0;
    float line = 1.0 - smoothstep(0.0, max(fwidth(h), 0.6), contour);
    shade -= line * 0.17 * step(1.0, h);
    shade = mix(shade, 0.29, smoothstep(0.2, 0.8, max(sea, river)));
    COLOR = vec4(vec3(shade), 1.0);
}
