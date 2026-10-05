extends SceneTree
## 기존 맵 없이 실제 교량 프리뷰 렌더를 저장한다.

var panel
var index := 0
var frame := 0

func _initialize() -> void:
	panel = load("res://scenes/railway_bridge_preview.tscn").instantiate()
	root.add_child.call_deferred(panel)

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 8:
		panel.select_model(index)
	if frame == 20:
		if panel.preview.model == null:
			push_error("철도 교량 프리뷰 모델 없음")
			quit(1)
			return true
		var image: Image = panel.preview.viewport.get_texture().get_image()
		var data: Dictionary = panel.models[index]
		var path := "res://assets/generated/railway_bridges/%s_preview.png" % data.id
		if image.save_png(path) != OK:
			quit(2)
			return true
		print("RENDERED: ", data.id)
		index += 1
		frame = 0
		if index == panel.models.size():
			quit(0)
	return false
