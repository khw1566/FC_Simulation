extends SceneTree
## 원본 DEM의 해수면 저지대 중 지도 경계와 연결된 영역만 해수로 분리한다.
func _initialize() -> void:
	var folder := "res://assets/maps/kanmon_straits/"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "map_meta.json"))
	var image := Image.load_from_file(meta.assets.heightmap)
	image.convert(Image.FORMAT_RF)
	image.resize(2048, 2048, Image.INTERPOLATE_BILINEAR)
	var n := image.get_width()
	var candidate := PackedByteArray()
	candidate.resize(n * n)
	var sea := PackedByteArray()
	sea.resize(n * n)
	var threshold: float = (0.35 - meta.min_elevation) / (meta.max_elevation - meta.min_elevation)
	for y in range(n):
		for x in range(n):
			candidate[y * n + x] = 1 if image.get_pixel(x, y).r <= threshold else 0
	var queue := PackedInt32Array()
	for i in range(n):
		for index in [i, (n - 1) * n + i, i * n, i * n + n - 1]:
			if candidate[index] and not sea[index]:
				sea[index] = 255
				queue.append(index)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var x := index % n
		var y := index / n
		for next in [index - 1 if x > 0 else -1, index + 1 if x < n - 1 else -1, index - n if y > 0 else -1, index + n if y < n - 1 else -1]:
			if next >= 0 and candidate[next] and not sea[next]:
				sea[next] = 255
				queue.append(next)
	var path := folder + "north_kyushu_sea_mask.png"
	Image.create_from_data(n, n, false, Image.FORMAT_L8, sea).save_png(path)
	for id in ["kanmon_straits", "kyushu_wide"]:
		var meta_path := "res://assets/maps/%s/map_meta.json" % id
		var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		map.assets.sea_mask = path
		var file := FileAccess.open(meta_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(map, "  "))
	var manifest_path := "res://assets/generated/manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	manifest.assets.north_kyushu_sea_mask = {"file_path": path, "sha256": FileAccess.get_sha256(path), "bbox": meta.bbox, "elevation": {"min_meters": -50, "max_meters": 0.35}, "resolution": {"width": n, "height": n}, "source": meta.assets.heightmap, "method": "DEM sea-level flood fill from raster boundary"}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	print("해수 마스크 생성: ", queue.size(), " / ", n * n, " 픽셀")
	quit()
