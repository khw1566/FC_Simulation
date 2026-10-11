extends Node3D
## 원경 자산만 그림자 투사를 끈다. 원본 메시·씬에는 쓰지 않는다.
func _ready() -> void:
	_disable_shadows(self)

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)
