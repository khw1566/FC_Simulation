extends Control
class_name MapHUDView
signal travel_requested(world_xz: Vector2)
signal map_visibility_changed(open: bool)

const MapFovDrawerClass = preload("res://scripts/views/map_fov_drawer.gd")

@onready var minimap_container: Control = $MinimapContainer
@onready var minimap_clip: Control = $MinimapContainer/MarginContainer/MapClip
@onready var minimap_content: Control = $MinimapContainer/MarginContainer/MapClip/MapContent
@onready var minimap_tex: TextureRect = $MinimapContainer/MarginContainer/MapClip/MapContent/MapTexture
@onready var minimap_marker: TextureRect = $MinimapContainer/MarginContainer/MapClip/PlayerMarker
@onready var compass_needle: TextureRect = $MinimapContainer/CompassFrame/Needle

@onready var fullscreen_map_modal: Control = $FullscreenMapModal
@onready var fs_map_clip: Control = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/MapClip
@onready var fs_map_content: Control = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/MapClip/MapContent
@onready var fs_map_tex: TextureRect = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/MapClip/MapContent/MapTexture
@onready var fs_marker: TextureRect = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/MapClip/MapContent/PlayerMarker
@onready var coord_label: Label = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/CoordLabel

@onready var recenter_btn: Button = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/HeaderContainer/RecenterBtn
@onready var reset_btn: Button = $FullscreenMapModal/PanelContainer/MarginContainer/VBoxContainer/HeaderContainer/ResetBtn

# 미니맵 하단 상시 속도/마하수 표시 컨트롤
@onready var airspeed_box: Control = $AirspeedBox
@onready var val_tas_label: Label = $AirspeedBox/Margin/VBox/RowTAS/ValTAS
@onready var val_ias_label: Label = $AirspeedBox/Margin/VBox/RowIAS/ValIAS
@onready var val_mach_label: Label = $AirspeedBox/Margin/VBox/RowIAS/ValMach

var is_fullscreen_open: bool = false
var world_size: float = 28000.0 # 28km 광역 전역 크기
var minimap_view_size: float = 1000.0 # 미니맵이 커버하는 실세계 영역: 1,000m x 1,000m (1km²)

# 대형 맵 패닝/줌 상태 변수
var _is_dragging: bool = false
var _map_offset: Vector2 = Vector2.ZERO
var _zoom_level: float = 1.0

# 플레이어 상태 캐시
var _latest_player_pos: Vector3 = Vector3.ZERO
var _latest_player_yaw: float = 0.0
var _latest_player_fov: float = 70.0

# FOV 시야각 드로어 인스턴스
var _minimap_fov_drawer: Control = null
var _fs_fov_drawer: Control = null
var _district_overlay: Control

func _ready() -> void:
	fullscreen_map_modal.visible = false
	_init_from_map_selection()
	_load_runtime_textures()
	_setup_fov_drawers()
	_bind_buttons()
	_setup_map_browser()
	fs_map_clip.resized.connect(_layout_map_square)
	_layout_map_square.call_deferred()

func _setup_map_browser() -> void:
	var box := fs_map_clip.get_parent()
	var close_button := Button.new()
	close_button.text = "닫기 [M]"
	box.get_node("HeaderContainer").add_child(close_button)
	close_button.pressed.connect(toggle_fullscreen_map)
	var tabs := TabBar.new()
	tabs.add_tab("지도 보기")
	tabs.add_tab("행정구역 탐색")
	var selected_service := get_node_or_null("/root/MapSelectionService")
	if selected_service and selected_service.selected_map and selected_service.selected_map.districts_path.is_empty():
		tabs.set_tab_disabled(1, true)
	box.add_child(tabs)
	box.move_child(tabs, 1)
	var browser := preload("res://scripts/views/map_district_browser.gd").new()
	box.add_child(browser)
	box.move_child(browser, 2)
	browser.visible = false
	browser.district_selected.connect(_focus_district)
	tabs.tab_changed.connect(func(index): browser.visible = index == 1)
	var legend := Label.new()
	legend.text = "등고선 50m · 짙은 회색: 수계 · 테두리 실선: 주요도로 | 좌클릭: 위치 이동 · 우클릭 드래그: 지도 이동 · 휠: 확대"
	if selected_service and selected_service.selected_map:
		var meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s/map_meta.json" % selected_service.selected_map.id))
		if meta is Dictionary:
			legend.text = str(meta.get("tactical_atlas", {}).get("legend", legend.text))
			if meta.has("building_data"):
				legend.text += "\n건물 외곽선: © OpenStreetMap contributors / 国土地理院最適化ベクトルタイル · 높이 대부분 추정"
	legend.add_theme_font_size_override("font_size", 11)
	box.add_child(legend)
	box.move_child(legend, 3)
	_district_overlay = preload("res://scripts/views/map_district_overlay.gd").new()
	_district_overlay.world_size = world_size
	fs_map_tex.add_child(_district_overlay)
	for control in [fs_map_content, fs_map_tex, fs_marker, _fs_fov_drawer]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _layout_map_square() -> void:
	var side: float = minf(fs_map_clip.size.x, fs_map_clip.size.y)
	fs_map_tex.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	fs_map_tex.size = Vector2(side, side)
	if _district_overlay != null:
		_district_overlay.size = fs_map_tex.size
		_district_overlay.queue_redraw()
	reset_map_view()

func _focus_district(record: Dictionary) -> void:
	var points := PackedVector2Array()
	for point in record.get("polygon", []):
		points.append(Vector2(float(point[0]), float(point[1])))
	if points.is_empty():
		return
	_district_overlay.polygon = points
	_district_overlay.queue_redraw()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	bounds = bounds.intersection(Rect2(Vector2.ONE * -world_size * 0.5, Vector2.ONE * world_size))
	var ratio: float = maxf(bounds.size.x, bounds.size.y) / world_size
	_zoom_level = clampf(0.8 / maxf(ratio, 0.01), 1.0, 24.0)
	var center: Vector2 = (bounds.get_center() / world_size + Vector2.ONE * 0.5) * fs_map_tex.size
	_map_offset = fs_map_clip.size * 0.5 - center * _zoom_level
	_update_fs_transform()

func _init_from_map_selection() -> void:
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			var m = svc.selected_map
			world_size = m.world_size_meters
			
			# 해당 맵의 실측 BBOX 및 월드 크기로 전역 GeoCoordinateConverter 실시간 갱신
			var GeoConverter = load("res://scripts/core/geo_coordinate_converter.gd")
			GeoConverter.configure_bounds(m.bbox_south, m.bbox_north, m.bbox_west, m.bbox_east, world_size)
			print("[MapHUDView] Configured Geo bounds for map: ", m.id, " (world_size: ", world_size, "m)")

func _bind_buttons() -> void:
	if recenter_btn:
		recenter_btn.pressed.connect(recenter_on_player)
	if reset_btn:
		reset_btn.pressed.connect(reset_map_view)

func _setup_fov_drawers() -> void:
	# 미니맵용 FOV 드로어
	if minimap_clip:
		_minimap_fov_drawer = MapFovDrawerClass.new()
		_minimap_fov_drawer.name = "MinimapFovDrawer"
		minimap_clip.add_child(_minimap_fov_drawer)
		minimap_clip.move_child(_minimap_fov_drawer, minimap_marker.get_index())

	# 대형 지도용 FOV 드로어
	if fs_map_content:
		_fs_fov_drawer = MapFovDrawerClass.new()
		_fs_fov_drawer.name = "FsFovDrawer"
		fs_map_content.add_child(_fs_fov_drawer)
		fs_map_content.move_child(_fs_fov_drawer, fs_marker.get_index())

func _load_runtime_textures() -> void:
	var active_map_path: String = ""
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			active_map_path = svc.selected_map.tactical_map_path

	if active_map_path.is_empty() or not FileAccess.file_exists(active_map_path):
		var vector_path := "res://assets/maps/kanmon_straits/kanmon_vector_tactical_map.png"
		var height_path := "res://assets/maps/kanmon_straits/kanmon_heightmap_16bit.png"
		var legacy_vector := "res://assets/generated/kanmon_vector_tactical_map.png"
		var legacy_height := "res://assets/generated/kanmon_heightmap_16bit.png"

		if FileAccess.file_exists(vector_path):
			active_map_path = vector_path
		elif FileAccess.file_exists(legacy_vector):
			active_map_path = legacy_vector
		elif FileAccess.file_exists(height_path):
			active_map_path = height_path
		else:
			active_map_path = legacy_height

	if FileAccess.file_exists(active_map_path):
		var img := preload("res://scripts/services/map_image_preloader.gd").read(active_map_path)
		if img:
			var tex := ImageTexture.create_from_image(img)
			if minimap_tex:
				minimap_tex.texture = tex
			if fs_map_tex:
				fs_map_tex.texture = tex
			print("[MapHUDView] Loaded tactical map texture: ", active_map_path)
			var selection := get_node_or_null("/root/MapSelectionService")
			if selection != null and selection.selected_map != null:
				var vector_display = preload("res://scripts/services/vector_map_display.gd")
				vector_display.attach(selection.selected_map.id, minimap_tex, minimap_clip)
				vector_display.attach(selection.selected_map.id, fs_map_tex, fs_map_clip)

	var needle_path := "res://assets/compass_needle.png"
	if FileAccess.file_exists(needle_path):
		var n_img := Image.load_from_file(needle_path)
		if n_img and compass_needle:
			compass_needle.texture = ImageTexture.create_from_image(n_img)

	var marker_path := "res://assets/player_marker.png"
	if FileAccess.file_exists(marker_path):
		var m_img := Image.load_from_file(marker_path)
		if m_img:
			var m_tex := ImageTexture.create_from_image(m_img)
			if minimap_marker:
				minimap_marker.texture = m_tex
			if fs_marker:
				fs_marker.texture = m_tex

func toggle_fullscreen_map() -> void:
	is_fullscreen_open = !is_fullscreen_open
	map_visibility_changed.emit(is_fullscreen_open)
	fullscreen_map_modal.visible = is_fullscreen_open
	if is_fullscreen_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		reset_map_view()
	else:
		_is_dragging = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func reset_map_view() -> void:
	_zoom_level = 1.0
	_map_offset = (fs_map_clip.size - fs_map_tex.size) * 0.5
	_update_fs_transform()

func recenter_on_player() -> void:
	if not fs_map_clip or not fs_map_tex:
		return
	
	var u: float = clampf((_latest_player_pos.x + world_size * 0.5) / world_size, 0.0, 1.0)
	var v: float = clampf((_latest_player_pos.z + world_size * 0.5) / world_size, 0.0, 1.0)

	var tex_size := fs_map_tex.size
	var player_map_pt := Vector2(u * tex_size.x, v * tex_size.y)
	var clip_center := fs_map_clip.size * 0.5

	# 플레이어 위치가 클립 중심에 오도록 오프셋 계산
	_map_offset = clip_center - (player_map_pt * _zoom_level)
	_update_fs_transform()

func update_player_transform(player_pos: Vector3, player_yaw: float, fov_deg: float = 70.0) -> void:
	_latest_player_pos = player_pos
	_latest_player_yaw = player_yaw
	_latest_player_fov = fov_deg

	var u: float = clampf((player_pos.x + world_size * 0.5) / world_size, 0.0, 1.0)
	var v: float = clampf((player_pos.z + world_size * 0.5) / world_size, 0.0, 1.0)

	# 1. 미니맵 상세 지도(약 1km² = 1000m x 1000m) 플레이어 중심 로컬 뷰포트 업데이트
	if minimap_clip and minimap_content and minimap_tex:
		var mini_viewport_size := minimap_clip.size # 예: 184x184 px
		# 1000m 영역이 미니맵 뷰포트에 꽉 차도록 확대 배율(Scale) 계산
		# 28,000m 광역 지도가 1000m만 보이도록 확대: 28000 / 1000 = 28.0배
		var minimap_scale: float = world_size / minimap_view_size
		
		# 텍스처 원본 크기를 미니맵 뷰포트에 맞춘 기준 크기
		var base_tex_size := mini_viewport_size * minimap_scale
		minimap_tex.size = base_tex_size
		
		# 전체 지도 내에서 플레이어의 픽셀 위치
		var player_tex_pos := Vector2(u * base_tex_size.x, v * base_tex_size.y)
		var center_pt := mini_viewport_size * 0.5
		
		# 플레이어가 항상 미니맵의 중앙에 오도록 텍스처 컨테이너 오프셋 이동
		minimap_content.position = center_pt - player_tex_pos

		# 플레이어 마커 및 FOV 드로어는 미니맵 정중앙에 고정
		if minimap_marker:
			minimap_marker.position = center_pt - Vector2(9.0, 9.0)
			minimap_marker.rotation = -player_yaw

		if _minimap_fov_drawer:
			_minimap_fov_drawer.position = center_pt
			# 1km² 시야각 콘 반경 (미니맵 반경의 약 45% = 40px)
			_minimap_fov_drawer.update_fov(42.0, fov_deg, -player_yaw)

	if compass_needle:
		compass_needle.rotation = player_yaw

	# 2. 대형 지도 마커 및 시야각(FOV) 콘 업데이트
	if is_fullscreen_open:
		if fs_marker and fs_map_tex:
			var tex_size := fs_map_tex.size
			var fs_center := Vector2(u * tex_size.x, v * tex_size.y)
			fs_marker.position = fs_center - Vector2(12.0, 12.0)
			fs_marker.rotation = -player_yaw

			if _fs_fov_drawer:
				_fs_fov_drawer.position = fs_center
				_fs_fov_drawer.update_fov(75.0, fov_deg, -player_yaw)

		if coord_label:
			var GeoConverter = load("res://scripts/core/geo_coordinate_converter.gd")
			var geo: Dictionary = GeoConverter.world_to_geo(player_pos)
			coord_label.text = "위도: %.4f°N | 경도: %.4f°E | 고도: %.1fm | 좌표: (%.0fm, %.0fm) | 줌: %.1fx | FOV: %.0f°" % [
				geo["lat"], geo["lon"], player_pos.y, player_pos.x, player_pos.z, _zoom_level, fov_deg
			]

## 미니맵 하단 상시 TAS/IAS 및 아음속(0.8M 이상) 마하수 표기 갱신
func update_airspeed_display(tas_kmh: float, ias_kmh: float, mach: float) -> void:
	if val_tas_label:
		val_tas_label.text = "%4.0f km/h" % tas_kmh
	if val_ias_label:
		val_ias_label.text = "%4.0f km/h" % ias_kmh

	if val_mach_label:
		# 아음속 영역(0.80M 이상) 진입 시 마하수 표기 활성화
		if mach >= 0.80:
			val_mach_label.visible = true
			val_mach_label.text = "[M%.2f]" % mach
		else:
			val_mach_label.visible = false

func handle_fullscreen_gui_input(event: InputEvent) -> void:
	if not is_fullscreen_open:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var local: Vector2 = (event.position - _map_offset) / _zoom_level
			if Rect2(Vector2.ZERO, fs_map_tex.size).has_point(local):
				var point: Vector2 = (local / fs_map_tex.size - Vector2.ONE * 0.5) * world_size
				travel_requested.emit(point)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_is_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom_at_point(event.position, 1.20)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom_at_point(event.position, 1.0 / 1.20)

	elif event is InputEventMouseMotion and _is_dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			_is_dragging = false
			return
		_map_offset += event.relative
		_update_fs_transform()
	fs_map_clip.accept_event()

func _apply_zoom_at_point(mouse_pos: Vector2, zoom_factor: float) -> void:
	var old_zoom := _zoom_level
	var new_zoom := clampf(old_zoom * zoom_factor, 0.4, 24.0)
	if is_equal_approx(old_zoom, new_zoom):
		return

	# 마우스 커서 위치를 기준으로 줌인/줌아웃 (마우스 아래의 지도 위치 불변)
	_map_offset = mouse_pos - (mouse_pos - _map_offset) * (new_zoom / old_zoom)
	_zoom_level = new_zoom
	_update_fs_transform()

func _update_fs_transform() -> void:
	if fs_map_content:
		fs_map_content.scale = Vector2(_zoom_level, _zoom_level)
		fs_map_content.position = _map_offset
