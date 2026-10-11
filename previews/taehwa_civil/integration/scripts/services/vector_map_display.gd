extends RefCounted
## 준비된 벡터 지도 타일의 표시 노드를 HUD에 연결한다.

const Tiles = preload("res://scripts/views/vector_map_tiles.gd")


static func attach(map_id: String, texture: TextureRect, clip: Control) -> void:
	var meta_path := "res://assets/maps/%s/map_meta.json" % map_id
	if not FileAccess.file_exists(meta_path):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not meta is Dictionary:
		return
	var index_path := str(meta.get("simple_vector_map", {}).get("tiles_index", ""))
	if index_path.is_empty() or not FileAccess.file_exists(index_path):
		return
	var layer := Tiles.new()
	texture.add_child(layer)
	if not layer.configure(index_path, clip):
		layer.queue_free()
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
