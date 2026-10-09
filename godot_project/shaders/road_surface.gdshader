shader_type spatial;
render_mode cull_disabled;

uniform sampler2D road_heightmap : filter_nearest, repeat_disable;
uniform sampler2D terrain_lods : filter_nearest, repeat_disable;
uniform vec2 chunk_counts = vec2(8.0);
uniform float world_size = 60000.0;
uniform float terrain_base_resolution = 128.0;
uniform float min_elevation = -30.0;
uniform float max_elevation = 1250.0;
uniform float clearance = 1.2;
uniform vec3 road_color = vec3(0.18, 0.19, 0.20);

float sample_corner(vec2 uv, ivec2 origin, ivec2 span) {
	vec2 pixel = clamp(uv, vec2(0.0), vec2(1.0)) * vec2(span);
	ivec2 p = ivec2(floor(pixel));
	ivec2 q = min(p + ivec2(1), span);
	vec2 t = fract(pixel);
	t = t * t * (3.0 - 2.0 * t);
	float a = texelFetch(road_heightmap, origin + p, 0).r;
	float b = texelFetch(road_heightmap, origin + ivec2(q.x, p.y), 0).r;
	float c = texelFetch(road_heightmap, origin + ivec2(p.x, q.y), 0).r;
	float d = texelFetch(road_heightmap, origin + q, 0).r;
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 map_uv = clamp(world.xz / world_size + vec2(0.5), vec2(0.0), vec2(0.999999));
	vec2 tile_uv = map_uv * chunk_counts;
	ivec2 tile = ivec2(floor(tile_uv));
	float lod = texelFetch(terrain_lods, tile, 0).r;
	float resolution = terrain_base_resolution / exp2(clamp(round(lod), 0.0, 2.0));
	ivec2 image_size = textureSize(road_heightmap, 0);
	ivec2 tile_size = image_size / ivec2(chunk_counts);
	ivec2 origin = tile * tile_size;
	ivec2 span = min(tile_size, image_size - origin - ivec2(1));
	vec2 grid = fract(tile_uv) * resolution;
	vec2 cell = min(floor(grid), vec2(resolution - 1.0));
	vec2 f = grid - cell;
	float a = sample_corner(cell / resolution, origin, span);
	float b = sample_corner((cell + vec2(1, 0)) / resolution, origin, span);
	float c = sample_corner((cell + vec2(0, 1)) / resolution, origin, span);
	float d = sample_corner((cell + vec2(1, 1)) / resolution, origin, span);
	float h = (f.x + f.y <= 1.0) ? a + f.x * (b - a) + f.y * (c - a) : d + (1.0 - f.x) * (c - d) + (1.0 - f.y) * (b - d);
	VERTEX.y = min_elevation + h * (max_elevation - min_elevation) + clearance + UV2.y;
}

void fragment() {
	ALBEDO = road_color;
	ROUGHNESS = 0.95;
}
