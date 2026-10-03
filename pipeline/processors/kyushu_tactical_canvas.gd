extends Node2D
## 큐슈 지도 범위에 원본 DEM·기존 도로·공항을 같은 위경도로 합성한다.
var meta: Dictionary
var coastline: Dictionary
var airports: Array
var roads: Array
var source_meta: Dictionary
var dimension := 2048.0
var font := SystemFont.new()

func geo(lon: float, lat: float) -> Vector2:
	return Vector2((lon - meta.bbox.west) / (meta.bbox.east - meta.bbox.west), (meta.bbox.north - lat) / (meta.bbox.north - meta.bbox.south)) * dimension

func _draw() -> void:
	font.font_names = PackedStringArray(["Malgun Gothic"])
	for lon in range(int(ceil(meta.bbox.west)), int(floor(meta.bbox.east)) + 1):
		var x := geo(lon, 32).x
		draw_line(Vector2(x, 0), Vector2(x, dimension), Color(1, 1, 1, 0.16), 1)
		draw_string(font, Vector2(x + 8, 35), "%d°E" % lon, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	for lat in range(int(ceil(meta.bbox.south)), int(floor(meta.bbox.north)) + 1):
		var y := geo(130, lat).y
		draw_line(Vector2(0, y), Vector2(dimension, y), Color(1, 1, 1, 0.16), 1)
		draw_string(font, Vector2(12, y - 8), "%d°N" % lat, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	for road in roads:
		var points := PackedVector2Array()
		for p in road.points:
			var u: float = p[0] / source_meta.world_size_meters + 0.5
			var v: float = p[2] / source_meta.world_size_meters + 0.5
			points.append(geo(lerpf(source_meta.bbox.west, source_meta.bbox.east, u), lerpf(source_meta.bbox.north, source_meta.bbox.south, v)))
		if points.size() > 1:
			draw_polyline(points, Color("777777"), 1.4, true)
	var occupied: Array[Rect2] = []
	for airport in airports:
		var point := geo(airport.anchor.lon, airport.anchor.lat)
		draw_circle(point, 9, Color.BLACK)
		draw_circle(point, 5, Color.WHITE)
		var text: String = airport.name_ko
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		var pos := point + Vector2(16, -12)
		pos.x = clampf(pos.x, 15, dimension - size.x - 15)
		pos.y = clampf(pos.y, size.y + 15, dimension - 120)
		for attempt in range(20):
			var bounds := Rect2(pos - Vector2(4, size.y), size + Vector2(8, 8))
			var overlaps := false
			for used in occupied:
				if bounds.intersects(used):
					overlaps = true
					break
			if not overlaps:
				occupied.append(bounds)
				draw_line(point, pos + Vector2(0, -8), Color.BLACK, 1.5, true)
				draw_rect(bounds, Color(1, 1, 1, 0.88))
				draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.BLACK)
				break
			pos.y += 32
	draw_rect(Rect2(Vector2(0, dimension - 100), Vector2(dimension, 100)), Color("303030"))
	draw_string(font, Vector2(35, dimension - 65), "큐슈 · 북큐슈 구현 범위 · 공항 %d곳" % airports.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color.WHITE)
	draw_string(font, Vector2(35, dimension - 25), "원본 DEM / OurAirports · 2026-10-03 생성", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)


