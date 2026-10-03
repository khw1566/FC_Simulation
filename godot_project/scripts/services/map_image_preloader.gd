extends Node
class_name MapImagePreloader

var worker: Thread
var _mutex := Mutex.new()
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func prepare(paths: Array) -> Dictionary:
	worker = Thread.new()
	if worker.start(_read_images.bind(paths)) != OK:
		return {}
	while worker.is_alive():
		await get_tree().process_frame
	return worker.wait_to_finish()

func _read_images(paths: Array) -> Dictionary:
	var result: Dictionary = {}
	for path in paths:
		_mutex.lock()
		var stop := _cancelled
		_mutex.unlock()
		if stop:
			break
		if not str(path).is_empty() and not result.has(path) and FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty():
				result[path] = image
	return result

static func read(path: String) -> Image:
	var tree := Engine.get_main_loop() as SceneTree
	var loader := tree.root.get_node_or_null("LoadingManagerService") if tree else null
	if loader != null and loader.image_cache.has(path):
		return loader.image_cache[path]
	return Image.load_from_file(path)

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
