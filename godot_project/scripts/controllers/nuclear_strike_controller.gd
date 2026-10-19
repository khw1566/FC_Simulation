extends Node
class_name NuclearStrikeController

## 핵폭발 시뮬레이션 입력: B 위력 순환, V 조준점 투하, K 전체 제거.
## 지도 탐색 중이거나 일시 정지 중에는 입력을 받지 않는다.

var manager: Node
var player_node: Node

func _unhandled_input(event: InputEvent) -> void:
	if not manager or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if player_node and "map_navigation_active" in player_node and bool(player_node.get("map_navigation_active")):
		return
	match (event as InputEventKey).keycode:
		KEY_B:
			manager.call("cycle_yield")
		KEY_V:
			manager.call("drop_selected")
		KEY_K:
			manager.call("clear_all")
		_:
			return
	get_viewport().set_input_as_handled()
