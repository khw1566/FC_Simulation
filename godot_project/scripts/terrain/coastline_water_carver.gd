extends RefCounted
class_name CoastlineWaterCarver

## 수계 마스크 기반 해안선 거리 밴드 절토 및 지형 표고 정밀 샘플링 처리기

## 수계 마스크(이진 0/255)로부터 해안선 거리 밴드를 생성하고 지형 고도를 절토/호안 보정
static func apply_coastline_carving(heightmap: Image, watermask: Image, min_elevation: float, max_elevation: float) -> void:
	if not watermask or not heightmap:
		return

	var h_w: int = heightmap.get_width()
	var h_h: int = heightmap.get_height()
	var wm_w: int = watermask.get_width()
	var wm_h: int = watermask.get_height()

	var elev_range: float = max_elevation - min_elevation
	if elev_range <= 0.0:
		return

	var water_deep_norm: float = clampf((-5.0 - min_elevation) / elev_range, 0.0, 1.0)
	var coast_land_min_norm: float = clampf((0.35 - min_elevation) / elev_range, 0.0, 1.0)

	# 1단계: 수계마스크를 높이맵 해상도에 맞춰 이진 2D 배열로 변환
	var water_binary: Array = []
	water_binary.resize(h_h)
	for y in range(h_h):
		var row: Array[bool] = []
		row.resize(h_w)
		var v: float = float(y) / float(h_h - 1)
		var wm_y: int = int(clampf(v * float(wm_h - 1), 0.0, float(wm_h - 1)))
		for x in range(h_w):
			var u: float = float(x) / float(h_w - 1)
			var wm_x: int = int(clampf(u * float(wm_w - 1), 0.0, float(wm_w - 1)))
			row[x] = watermask.get_pixel(wm_x, wm_y).r >= 0.5
		water_binary[y] = row

	# 2단계: BFS 기반 해안선 거리 맵 생성 (해안선 경계에서의 픽셀 거리)
	var BAND_RADIUS: int = 6  # 해안선 경계 밴드 반경 (픽셀)
	var dist_map: Array = []
	dist_map.resize(h_h)
	for y2 in range(h_h):
		var drow: Array[int] = []
		drow.resize(h_w)
		for x2 in range(h_w):
			drow[x2] = 9999
		dist_map[y2] = drow

	# 해안선 경계 픽셀 탐색 (수역↔육지 인접 전환점)
	var queue: Array[Vector2i] = []
	for y3 in range(h_h):
		var w_row: Array[bool] = water_binary[y3]
		for x3 in range(h_w):
			var is_w: bool = w_row[x3]
			var is_edge: bool = false
			if x3 > 0 and (water_binary[y3][x3 - 1] != is_w):
				is_edge = true
			elif x3 < h_w - 1 and (water_binary[y3][x3 + 1] != is_w):
				is_edge = true
			elif y3 > 0 and (water_binary[y3 - 1][x3] != is_w):
				is_edge = true
			elif y3 < h_h - 1 and (water_binary[y3 + 1][x3] != is_w):
				is_edge = true
			if is_edge:
				dist_map[y3][x3] = 0
				queue.append(Vector2i(x3, y3))

	# BFS 확산 (BAND_RADIUS 범위 내)
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cd: int = dist_map[cur.y][cur.x]
		if cd >= BAND_RADIUS:
			continue
		for nb in [Vector2i(cur.x - 1, cur.y), Vector2i(cur.x + 1, cur.y), Vector2i(cur.x, cur.y - 1), Vector2i(cur.x, cur.y + 1)]:
			if nb.x < 0 or nb.x >= h_w or nb.y < 0 or nb.y >= h_h:
				continue
			if dist_map[nb.y][nb.x] <= cd + 1:
				continue
			dist_map[nb.y][nb.x] = cd + 1
			queue.append(nb)

	# 3단계: 거리 맵과 수계 이진 마스크를 조합하여 지형 고도 보정
	var modified_count: int = 0
	for y4 in range(h_h):
		var w_row4: Array[bool] = water_binary[y4]
		for x4 in range(h_w):
			var cur_h: float = heightmap.get_pixel(x4, y4).r
			var is_water: bool = w_row4[x4]
			var d: int = dist_map[y4][x4]
			var new_h: float = cur_h

			# 높은 내륙 하천·호수까지 해수면 아래로 파내지 않는다.
			var original_meters: float = min_elevation + cur_h * elev_range
			if is_water and original_meters <= 8.0:
				if d >= BAND_RADIUS:
					new_h = minf(cur_h, water_deep_norm)
				elif d == 0:
					var edge_norm: float = clampf((-0.35 - min_elevation) / elev_range, 0.0, 1.0)
					new_h = minf(cur_h, edge_norm)
				else:
					var t: float = float(d) / float(BAND_RADIUS)
					var depth_m: float = lerpf(-0.35, -5.0, t * t * (3.0 - 2.0 * t))
					var target: float = clampf((depth_m - min_elevation) / elev_range, 0.0, 1.0)
					new_h = minf(cur_h, target)
			elif not is_water:
				if d <= 2 and d < 9999:
					new_h = maxf(cur_h, coast_land_min_norm)
				elif d <= BAND_RADIUS and d < 9999:
					var min_land_norm: float = clampf((0.15 - min_elevation) / elev_range, 0.0, 1.0)
					new_h = maxf(cur_h, min_land_norm)

			if new_h != cur_h:
				heightmap.set_pixel(x4, y4, Color(new_h, new_h, new_h, 1.0))
				modified_count += 1

	print("[CoastlineWaterCarver] Distance-band carving: %d texels adjusted (Band radius: %d px)." % [modified_count, BAND_RADIUS])

## 특정 월드 좌표(world_x, world_z)에서의 지형 표고를 높이맵 이미지로부터 바이리니어 보간 샘플링
static func sample_elevation_bilinear(heightmap: Image, world_x: float, world_z: float, world_size: float, min_elevation: float, max_elevation: float) -> float:
	if not heightmap:
		return min_elevation

	var half_size: float = world_size * 0.5
	var u: float = (world_x + half_size) / world_size
	var v: float = (world_z + half_size) / world_size

	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return min_elevation

	var img_w: int = heightmap.get_width()
	var img_h: int = heightmap.get_height()

	var fx: float = clampf(u * float(img_w - 1), 0.0, float(img_w - 1))
	var fy: float = clampf(v * float(img_h - 1), 0.0, float(img_h - 1))

	var x0: int = int(fx)
	var y0: int = int(fy)
	var x1: int = mini(x0 + 1, img_w - 1)
	var y1: int = mini(y0 + 1, img_h - 1)

	var dx: float = fx - float(x0)
	var dy: float = fy - float(y0)

	var h00: float = heightmap.get_pixel(x0, y0).r
	var h10: float = heightmap.get_pixel(x1, y0).r
	var h01: float = heightmap.get_pixel(x0, y1).r
	var h11: float = heightmap.get_pixel(x1, y1).r

	var h_top: float = lerpf(h00, h10, dx)
	var h_bot: float = lerpf(h01, h11, dx)
	var norm_h: float = lerpf(h_top, h_bot, dy)

	return min_elevation + norm_h * (max_elevation - min_elevation)
