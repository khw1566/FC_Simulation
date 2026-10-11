extends Node
class_name MapImagePreloader

var worker: Thread
var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func prepare(paths: Array, height_path: String = "", height_width: int = 0) -> Dictionary:
	worker = Thread.new()
	if worker.start(_read_images.bind(paths, height_path, height_width)) != OK:
		return {}
	while worker.is_alive():
		await get_tree().process_frame
	return worker.wait_to_finish()

func _read_images(paths: Array, height_path: String, height_width: int) -> Dictionary:
	var result: Dictionary = {}
	for path in paths:
		_mutex.lock()
		var stop := _cancelled
		_mutex.unlock()
		if stop:
			break
		if not str(path).is_empty() and not result.has(path) and FileAccess.file_exists(path):
			var image := _decode(path)
			if image != null and not image.is_empty():
				if path == height_path and height_width > 0 and image.get_width() > height_width:
					# 원본 크기의 이미지도 작업 스레드에서 RF로 변환·축소한다.
					image.convert(Image.FORMAT_RF)
					var height := roundi(float(image.get_height()) * height_width / image.get_width())
					image.resize(height_width, height, Image.INTERPOLATE_BILINEAR)
				result[path] = image
	return result

static func read(path: String) -> Image:
	var tree := Engine.get_main_loop() as SceneTree
	var loader := tree.root.get_node_or_null("LoadingManagerService") if tree else null
	if loader != null and loader.image_cache.has(path):
		return loader.image_cache[path]
	return _decode(path)

static func _decode(path: String) -> Image:
	if not path.ends_with(".rf32z"):
		return Image.load_from_file(path)
	var packed := FileAccess.get_file_as_bytes(path)
	if packed.size() < 8:
		return null
	var width := packed.decode_u32(0)
	var height := packed.decode_u32(4)
	if width < 1 or height < 1 or width > 8192 or height > 8192:
		return null
	var expected := width * height * 4
	var pixels := packed.slice(8).decompress(expected, FileAccess.COMPRESSION_DEFLATE)
	if pixels.size() != expected:
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RF, pixels)

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
