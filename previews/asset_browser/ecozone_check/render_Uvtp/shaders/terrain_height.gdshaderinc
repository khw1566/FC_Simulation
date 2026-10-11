// 렌더된 지형 메시와 같은 높이를 GPU에서 구한다. 지형 청크의 현재 LOD 격자 삼각형을 그대로 따라가므로
// 거친 지도에서도 식생 밑동이 지면에 붙는다. 계산식은 road_surface.gdshader와 같고, 균일 변수는
// TerrainChunkManager.create_road_material()이 만든 값을 그대로 복사해 쓴다(th_ 접두어).

uniform sampler2D th_heightmap : filter_nearest, repeat_disable;
uniform sampler2D th_terrain_lods : filter_nearest, repeat_disable;
uniform bool th_enabled = false;
uniform vec2 th_chunk_counts = vec2(8.0);
uniform float th_world_size = 60000.0;
uniform float th_base_resolution = 128.0;
uniform float th_min_elevation = -30.0;
uniform float th_max_elevation = 1250.0;
uniform float th_fallback_height = 0.0;

float th_corner(vec2 uv, ivec2 origin, ivec2 span) {
	vec2 pixel = clamp(uv, vec2(0.0), vec2(1.0)) * vec2(span);
	ivec2 p = ivec2(floor(pixel));
	ivec2 q = min(p + ivec2(1), span);
	vec2 t = fract(pixel);
	t = t * t * (3.0 - 2.0 * t);
	float a = texelFetch(th_heightmap, origin + p, 0).r;
	float b = texelFetch(th_heightmap, origin + ivec2(q.x, p.y), 0).r;
	float c = texelFetch(th_heightmap, origin + ivec2(p.x, q.y), 0).r;
	float d = texelFetch(th_heightmap, origin + q, 0).r;
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

float terrain_height(vec2 world_xz) {
	if (!th_enabled) {
		return th_fallback_height;
	}
	vec2 map_uv = clamp(world_xz / th_world_size + vec2(0.5), vec2(0.0), vec2(0.999999));
	vec2 tile_uv = map_uv * th_chunk_counts;
	ivec2 tile = ivec2(floor(tile_uv));
	float lod = texelFetch(th_terrain_lods, tile, 0).r;
	float resolution = th_base_resolution / exp2(clamp(round(lod), 0.0, 2.0));
	ivec2 image_size = textureSize(th_heightmap, 0);
	ivec2 tile_size = image_size / ivec2(th_chunk_counts);
	ivec2 origin = tile * tile_size;
	ivec2 span = min(tile_size, image_size - origin - ivec2(1));
	vec2 grid = fract(tile_uv) * resolution;
	vec2 cell = min(floor(grid), vec2(resolution - 1.0));
	vec2 f = grid - cell;
	float a = th_corner(cell / resolution, origin, span);
	float b = th_corner((cell + vec2(1, 0)) / resolution, origin, span);
	float c = th_corner((cell + vec2(0, 1)) / resolution, origin, span);
	float d = th_corner((cell + vec2(1, 1)) / resolution, origin, span);
	float h = (f.x + f.y <= 1.0) ? a + f.x * (b - a) + f.y * (c - a) : d + (1.0 - f.x) * (c - d) + (1.0 - f.y) * (b - d);
	return th_min_elevation + h * (th_max_elevation - th_min_elevation);
}
