extends Control
## 수동 생성된 SVG 타일을 현재 화면 해상도로만 표시한다.

var clip: Control
var grid := 16
var svg_size := 256
var folder := ""
var cache: Dictionary = {}
var cache_bytes := 0
var pending: Array[String] = []
var visible_tiles: Array[Dictionary] = []
var timer := 0.0
var stroke_limits: Dictionary = {}
const MAX_CACHE_BYTES := 64 * 1024 * 1024


func configure(index_path: String, clip_control: Control) -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not parsed is Dictionary:
		return false
	grid = int(parsed.get("grid", 16))
	svg_size = int(parsed.get("tile_svg_size", 256))
	if grid < 1 or grid > 64 or svg_size < 1:
		return false
	folder = index_path.get_base_dir()
	var colors: Dictionary = parsed.get("colors", {})
	for entry in [["roads", 5.0], ["railways", 2.0], ["coastline", 2.0], ["rivers", 3.0], ["shipping_routes", 2.0]]:
		if colors.has(entry[0]):
			stroke_limits[colors[entry[0]]] = entry[1]
	clip = clip_control
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return true


func _process(delta: float) -> void:
	if not is_visible_in_tree() or clip == null or size.x < 1 or size.y < 1:
		return
	timer += delta
	if timer >= 0.12:
		timer = 0.0
		_update_visible()
	if not pending.is_empty():
		_load_tile(pending.pop_front())
		queue_redraw()


func _update_visible() -> void:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var a := inverse * clip.global_position
	var b := inverse * (clip.global_position + clip.size)
	var region := Rect2(a, b - a).abs().intersection(Rect2(Vector2.ZERO, size))
	var scale_factor := get_global_transform_with_canvas().x.length()
	var screen_tile := size.x / grid * scale_factor
	visible_tiles.clear()
	if screen_tile < 140.0 or not region.has_area():
		pending.clear()
		queue_redraw()
		return
	var pixels := 256
	while pixels < screen_tile * 1.25 and pixels < 2048:
		pixels *= 2
	var lo := Vector2i(floor(region.position.x / size.x * grid), floor(region.position.y / size.y * grid))
	var hi := Vector2i(floor(region.end.x / size.x * grid), floor(region.end.y / size.y * grid))
	var next_pending: Array[String] = []
	for y in range(maxi(0, lo.y), mini(grid - 1, hi.y) + 1):
		for x in range(maxi(0, lo.x), mini(grid - 1, hi.x) + 1):
			var key := "%d_%d_%d" % [x, y, pixels]
			var rect := Rect2(Vector2(x, y) * size / grid, size / grid)
			visible_tiles.append({"key": key, "rect": rect})
			if cache.has(key):
				cache[key].used = Time.get_ticks_msec()
			else:
				next_pending.append(key)
	pending = next_pending
	queue_redraw()


func _load_tile(key: String) -> void:
	if cache.has(key):
		return
	var parts := key.split("_")
	var path := "%s/tiles/%s_%s.svg" % [folder, parts[0], parts[1]]
	if not FileAccess.file_exists(path):
		return
	var pixels := int(parts[2])
	var image := Image.new()
	var scale_factor := float(pixels) / svg_size
	var source := _style_svg(FileAccess.get_file_as_string(path), scale_factor)
	var error := image.load_svg_from_string(source, scale_factor)
	if error != OK or image.is_empty():
		return
	var bytes := image.get_width() * image.get_height() * 4
	while cache_bytes + bytes > MAX_CACHE_BYTES and not cache.is_empty():
		var oldest := ""
		var age := 9223372036854775807
		for candidate in cache:
			if int(cache[candidate].used) < age:
				oldest = candidate
				age = int(cache[candidate].used)
		cache_bytes -= int(cache[oldest].bytes)
		cache.erase(oldest)
	cache[key] = {"texture": ImageTexture.create_from_image(image), "bytes": bytes, "used": Time.get_ticks_msec()}
	cache_bytes += bytes


func _style_svg(source: String, display_scale: float) -> String:
	# 확대 시 선로·도로 선폭까지 커져 지도를 덮지 않도록 표시 폭을 제한한다.
	var regex := RegEx.new()
	regex.compile('stroke="([^\"]+)" stroke-width="([0-9.]+)"')
	var parts := PackedStringArray()
	var offset := 0
	for match in regex.search_all(source):
		parts.append(source.substr(offset, match.get_start() - offset))
		var color := match.get_string(1)
		var width := float(match.get_string(2))
		if stroke_limits.has(color):
			width = minf(width, float(stroke_limits[color]) / display_scale)
		parts.append('stroke="%s" stroke-width="%.4f"' % [color, width])
		offset = match.get_end()
	parts.append(source.substr(offset))
	return "".join(parts)


func _draw() -> void:
	for tile in visible_tiles:
		if cache.has(tile.key):
			draw_texture_rect(cache[tile.key].texture, tile.rect, false)
