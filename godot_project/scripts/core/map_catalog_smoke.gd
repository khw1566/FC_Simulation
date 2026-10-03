extends SceneTree
## 여섯 맵의 분류·파일 참조·선택 UI와 언어 전환을 검증한다.
const EXPECTED := {
	"kanmon_straits": "japan", "kyushu_wide": "japan",
	"ulsan_uc_west": "korea", "ulsan_metro_80km": "korea",
	"southeast_mega_140km": "korea", "flat_testing": "testing"
}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _expect(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)

func _run() -> void:
	var service := root.get_node("MapSelectionService")
	_expect(service.maps.size() == 6, "등록된 맵 수")
	for model in service.maps:
		_expect(EXPECTED.get(model.id) == model.category, "맵 분류: " + model.id)
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://assets/maps/%s/map_meta.json" % model.id))
		for key in meta.assets:
			_expect(FileAccess.file_exists(str(meta.assets[key])), "자산 누락: " + str(meta.assets[key]))
		_expect(FileAccess.file_exists(model.preview_image), "미리보기 누락: " + model.id)
	_expect(not service.select_map_by_id("ulsan_metro_60km"), "울산 60km 제외")
	_expect(not service.select_map_by_id("shimonoseki_port_3km"), "시모노세키항 제외")
	change_scene_to_file("res://scenes/ui/map_selection_menu.tscn")
	for i in range(4):
		await process_frame
	var menu := current_scene
	for language in ["ko", "en", "ko"]:
		menu.populate_map_list(service.maps, service.selected_map.id, language)
		_expect(menu.map_list_container.get_child_count() == 9, "분류 3개 및 버튼 6개: " + language)
		for id in EXPECTED:
			menu._map_buttons[id].pressed.emit()
			_expect(service.selected_map.id == id, "맵 선택: " + id)
	var airport: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/airport/placement.json"))
	_expect(FileAccess.file_exists(airport.scene_path), "공용 공항 모델")
	var airport_scene := load(airport.scene_path) as PackedScene
	_expect(airport_scene != null, "공항 씬 파싱")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../results/261003_map_categories.png")
	var result := {"passed": failures.is_empty(), "map_count": service.maps.size(), "failures": failures}
	var output := FileAccess.open("res://../results/261003_map_catalog_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
