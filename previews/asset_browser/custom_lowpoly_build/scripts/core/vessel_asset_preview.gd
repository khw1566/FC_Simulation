extends Node3D
## 월드 데이터 없이 선박 한 종류씩 표시하는 독립 프리뷰.

const CameraController = preload("res://scripts/player/vessel_preview_camera.gd")
const VESSELS = [
	["container_ship", "컨테이너선", 180.0, 28.0],
	["tugboat", "예인선", 30.0, 10.0],
	["motor_boat", "보트", 12.0, 3.8],
	["lpg_carrier", "LPG선", 145.0, 24.0],
	["oil_tanker", "유조선", 210.0, 34.0],
	["fishing_boat", "어업용 소형선박", 18.0, 5.4],
]

var model: Node3D
var camera: Camera3D
var details: Label
var water: MeshInstance3D
var buttons: Array[Button] = []


func _ready() -> void:
	_build_stage()
	_build_ui()
	_select_vessel(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.075, 0.08, 0.09)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 1.25
	add_child(light)
	camera = CameraController.new()
	camera.current = true
	camera.fov = 48
	add_child(camera)
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	water.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.18, 0.20)
	material.roughness = 0.65
	water.material_override = material
	add_child(water)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.04, 0.94)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = "해상 선박 에셋 프리뷰"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	for i in range(VESSELS.size()):
		var button := Button.new()
		button.text = VESSELS[i][1]
		button.pressed.connect(_select_vessel.bind(i))
		row.add_child(button)
		buttons.append(button)
	details = Label.new()
	column.add_child(details)
	var controls := Label.new()
	controls.text = "마우스 드래그: 회전  /  휠: 확대  /  R: 초기화  /  Esc: 종료\n각 선박은 화면에 맞춰 축소 표시됩니다."
	column.add_child(controls)
	var toggle := CheckButton.new()
	toggle.text = "수면 표시 (해제 시 선체 하부 확인)"
	toggle.button_pressed = true
	toggle.toggled.connect(func(visible_water: bool): water.visible = visible_water)
	column.add_child(toggle)


func _select_vessel(index: int) -> void:
	var spec: Array = VESSELS[index]
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file("res://assets/generated/vessels/%s.glb" % spec[0], state)
	if error != OK:
		details.text = "선박 파일을 읽을 수 없습니다: %s (오류 %d)" % [spec[0], error]
		return
	var next_model := document.generate_scene(state)
	if next_model == null:
		details.text = "선박 메시 생성에 실패했습니다: %s" % spec[0]
		return
	if is_instance_valid(model):
		model.free()
	model = next_model
	var display_scale: float = 24.0 / spec[2]
	model.scale = Vector3.ONE * display_scale
	add_child(model)
	details.text = "%s  |  길이 %.1f m × 폭 %.1f m  |  표시 축척 %.3f" % [spec[1], spec[2], spec[3], display_scale]
	for i in range(buttons.size()):
		buttons[i].disabled = i == index
	camera.reset_view()
