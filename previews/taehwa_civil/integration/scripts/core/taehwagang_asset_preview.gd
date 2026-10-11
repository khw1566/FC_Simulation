extends Node3D
## 기존 지도 없이 태화강역 에셋만 선택하여 표시한다.

const CameraController = preload("res://scripts/player/vessel_preview_camera.gd")
const ASSETS = [
	["taehwagang_complete", "전체 구역"],
	["station", "역사"],
	["rail_yard", "승강장·선로"],
	["forecourt", "광장·환승·주차"],
	["district", "주변 구역"],
]

var model: Node3D
var camera: Camera3D
var details: Label


func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.08, 0.08, 0.08)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.45
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.8
	add_child(light)
	camera = CameraController.new()
	camera.current = true
	camera.fov = 48
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.94)
	for margin in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + margin, 14.0)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "태화강역 및 역전 구역 에셋"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	for spec in ASSETS:
		var button := Button.new()
		button.text = spec[1]
		button.pressed.connect(_select.bind(spec[0]))
		row.add_child(button)
	details = Label.new()
	column.add_child(details)
	var help := Label.new()
	help.text = "공개 외관 참고 / 비실측 근사 모델\n드래그: 회전 / 휠: 확대 / R: 초기화 / Esc: 종료"
	column.add_child(help)
	_select("taehwagang_complete")


func _select(key: String) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := "res://assets/generated/taehwagang/%s.glb" % key
	var error := document.append_from_file(path, state)
	if error != OK:
		details.text = "에셋 로딩 실패: %s (%d)" % [key, error]
		return
	var next_model := document.generate_scene(state)
	if next_model == null:
		details.text = "메시 생성 실패: " + key
		return
	if is_instance_valid(model):
		model.free()
	model = next_model
	var mesh_instance := model.get_child(0) as MeshInstance3D
	if mesh_instance == null:
		model.free()
		details.text = "메시 노드가 없습니다: " + key
		return
	var bounds := mesh_instance.get_aabb()
	var factor := 24.0 / maxf(bounds.size.x, bounds.size.z)
	model.scale = Vector3.ONE * factor
	model.position = -bounds.get_center() * factor + Vector3(0, 2, 0)
	add_child(model)
	if key in ["station", "taehwagang_complete"]:
		var sign := Label3D.new()
		sign.text = "태화강역"
		sign.font_size = 96
		sign.pixel_size = 0.012
		sign.position = Vector3(0, 16.5, 21.5)
		sign.modulate = Color.WHITE
		sign.outline_modulate = Color.BLACK
		model.add_child(sign)
	for spec in ASSETS:
		if spec[0] == key:
			details.text = "%s / 마우스로 회전하거나 확대하여 확인하세요." % spec[1]
	camera.reset_view()
