extends VBoxContainer
## 행정 레벨과 이름으로 경계를 탐색한다. 선택은 지도 초점만 변경한다.
signal district_selected(record: Dictionary)
var records: Array = []
var matches: Array = []
var search: LineEdit
var level: OptionButton
var list: ItemList

func _ready() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	search = LineEdit.new()
	search.placeholder_text = "행정구역 이름 검색"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(search)
	level = OptionButton.new()
	for label in ["전체", "시도", "시군구", "읍면동", "리"]:
		level.add_item(label)
	row.add_child(level)
	list = ItemList.new()
	list.custom_minimum_size.y = 100
	add_child(list)
	search.text_changed.connect(func(_text): refresh())
	level.item_selected.connect(func(_index): refresh())
	list.item_selected.connect(func(index): district_selected.emit(matches[index]))
	var service := get_node_or_null("/root/MapSelectionService")
	if service != null and service.selected_map != null:
		var path: String = service.selected_map.districts_path
		if FileAccess.file_exists(path):
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Array:
				records = data
	refresh()

func refresh() -> void:
	list.clear()
	matches.clear()
	var levels := [-1, 4, 6, 8, 10]
	for record in records:
		var name: String = str(record.get("name_ko", ""))
		if not search.text.is_empty() and not name.contains(search.text):
			continue
		if level.selected > 0 and int(record.get("admin_level", -1)) != levels[level.selected]:
			continue
		matches.append(record)
		list.add_item("%s  ·  %s" % [name, str(record.get("boundary_id", record.get("id", "")))])
