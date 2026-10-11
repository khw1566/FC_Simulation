extends RefCounted
## 해수 마스크 영역을 해수면 아래로 제한한다. 내륙 하천은 변경하지 않는다.
static func apply(heightmap: Image, sea: Image, min_y: float, max_y: float) -> void:
	if sea == null:
		return
	var target := clampf((-1.0 - min_y) / (max_y - min_y), 0, 1)
	for y in range(heightmap.get_height()):
		var sy := mini(sea.get_height() - 1, y * sea.get_height() / heightmap.get_height())
		for x in range(heightmap.get_width()):
			var sx := mini(sea.get_width() - 1, x * sea.get_width() / heightmap.get_width())
			if sea.get_pixel(sx, sy).r >= 0.5:
				var h := heightmap.get_pixel(x, y).r
				if h > target:
					heightmap.set_pixel(x, y, Color(target, 0, 0))
