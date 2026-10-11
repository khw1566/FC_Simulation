extends CanvasLayer
## F9 커스텀 오브젝트 열람 도구. 원본 월드와 분리된 미리보기 사용.

const Catalog = preload("res://scripts/services/custom_asset_catalog.gd")
const Preview = preload("res://scripts/views/custom_asset_preview.gd")
var _panel: PanelContainer
var _preview: Preview
var _list: ItemList
var _tree: Tree
var _info: RichTextLabel
var _search: LineEdit
var _entries: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _selected: Dictionary = {}
var _was_paused := false
var _mouse_mode := Input.MOUSE_MODE_CAPTURED
var _open := false
var _launcher: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_launcher = Button.new()
	_launcher.text = "F9 · 오브젝트 열람"
	_launcher.position = Vector2(16, 16)
	_launcher.pressed.connect(_toggle)
	add_child(_launcher)
	_launcher.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_launcher.position = Vector2(16, -46)
	_build_ui()
	_panel.hide()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.035, 0.035)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_color", "Button", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color(0.16, 0.16, 0.16) if state == "normal" else Color(0.28, 0.28, 0.28)
		button_style.set_content_margin_all(8)
		theme.set_stylebox(state, "Button", button_style)
	for control_type in ["ItemList", "Tree"]:
		for state in ["selected", "selected_focus", "cursor", "cursor_unfocused"]:
			var selection := StyleBoxFlat.new()
			selection.bg_color = Color(0.30, 0.30, 0.30)
			theme.set_stylebox(state, control_type, selection)
	_panel.theme = theme
	var column := VBoxContainer.new()
	_panel.add_child(column)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	var title := Label.new()
	title.text = "커스텀 오브젝트 디버거"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	_button(toolbar, "목록 갱신", _reload)
	_button(toolbar, "전체 보기", func(): _preview.frame(_preview.bounds))
	var rotate := CheckButton.new()
	rotate.text = "자동 회전"
	rotate.toggled.connect(func(value: bool): _preview.auto_rotate = value)
	toolbar.add_child(rotate)
	_button(toolbar, "닫기 · F9 / Esc", _close)
	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 260
	content.add_child(sidebar)
	_search = LineEdit.new()
	_search.placeholder_text = "이름으로 검색"
	_search.text_changed.connect(func(_text: String): _filter())
	sidebar.add_child(_search)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 170
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	sidebar.add_child(_list)
	var parts := Label.new()
	parts.text = "부재 선택 · 클릭하면 해당 부분에 초점"
	sidebar.add_child(parts)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size.y = 140
	_tree.item_selected.connect(_select_part)
	sidebar.add_child(_tree)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)
	_preview = Preview.new()
	right.add_child(_preview)
	_info = RichTextLabel.new()
	_info.custom_minimum_size.y = 105
	_info.selection_enabled = true
	right.add_child(_info)
	var help := Label.new()
	help.text = "드래그: 회전  |  휠: 확대/축소  |  Shift + 드래그: 화면 이동  |  원본 자산 미리보기이며 지도 배치 고도는 적용되지 않습니다."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)

func _button(parent: Node, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle()
			get_viewport().set_input_as_handled()
		elif _open and event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if _open:
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if _open:
		_close()
		return
	_was_paused = get_tree().paused
	_mouse_mode = Input.mouse_mode
	_open = true
	get_tree().set_meta("custom_asset_debugger_open", true)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_panel.show()
	_launcher.hide()
	_preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_reload()

func _close() -> void:
	if not _open:
		return
	_open = false
	get_tree().remove_meta("custom_asset_debugger_open")
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode
	_panel.hide()
	_launcher.show()
	_preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree.clear()
	_preview.clear_model()

func _exit_tree() -> void:
	if _open:
		get_tree().remove_meta("custom_asset_debugger_open")
		get_tree().paused = _was_paused
		Input.mouse_mode = _mouse_mode

func _reload() -> void:
	_entries = Catalog.collect()
	_filter()

func _filter() -> void:
	_list.clear()
	_filtered.clear()
	for entry in _entries:
		if _search.text.is_empty() or str(entry.name).to_lower().contains(_search.text.to_lower()):
			_filtered.append(entry)
			_list.add_item(str(entry.name))
	if not _filtered.is_empty():
		_list.select(0)
		_select(0)
	else:
		_tree.clear()
		_preview.clear_model()
		_info.text = "해당하는 오브젝트가 없습니다."

func _select(index: int) -> void:
	_tree.clear()
	_selected = _filtered[index]
	var error: String = _preview.show_scene(str(_selected.path))
	if not error.is_empty():
		_info.text = error + "\n" + str(_selected.path)
		return
	_add_part(_preview.model, null)
	var box: AABB = _preview.bounds
	_info.text = "%s\n크기 X/Y/Z: %.2f / %.2f / %.2f m\n%s\n부재 목록에서 선택하면 이름·종류·좌표를 확인할 수 있습니다." % [_selected.name, box.size.x, box.size.y, box.size.z, _selected.path]

func _add_part(node: Node, parent: TreeItem) -> void:
	var item := _tree.create_item(parent)
	item.set_text(0, str(node.name))
	item.set_metadata(0, node)
	item.collapsed = parent != null
	for child in node.get_children():
		_add_part(child, item)

func _select_part() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var node: Node = item.get_metadata(0)
	if not is_instance_valid(node):
		return
	var box: AABB = _preview.measure(node)
	if box.size.length_squared() > 0.0:
		_preview.frame(box)
	var position := Vector3.ZERO
	if node is Node3D:
		position = node.global_position
	_info.text = "%s · %s\n미리보기 좌표: %.2f, %.2f, %.2f m\n범위: %.2f × %.2f × %.2f m\n%s" % [node.name, node.get_class(), position.x, position.y, position.z, box.size.x, box.size.y, box.size.z, _selected.path]
	if node is MeshInstance3D and node.mesh != null:
		_info.text += "\n메시 표면: %d | 재질: %s" % [node.mesh.get_surface_count(), str(node.material_override)]
	elif node is MultiMeshInstance3D and node.multimesh != null:
		_info.text += "\n반복 인스턴스: %d" % node.multimesh.instance_count
