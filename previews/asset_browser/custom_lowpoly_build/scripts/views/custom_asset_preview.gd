extends SubViewportContainer
## 별도 월드에 모델을 표시하고 궤도 카메라를 제어한다.

var viewport: SubViewport
var camera: Camera3D
var model: Node3D
var target := Vector3.ZERO
var distance := 100.0
var yaw := 0.65
var pitch := 0.35
var auto_rotate := false
var bounds := AABB()
var _dragging := false

func _ready() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.handle_input_locally = false
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.07, 0.07)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	gui_input.connect(_orbit_input)

func show_scene(path: String) -> String:
	clear_model()
	var packed := load(path) as PackedScene
	if packed == null:
		return "씬 파일을 열 수 없습니다."
	var instance := packed.instantiate()
	if not instance is Node3D:
		instance.free()
		return "3D 오브젝트 씬이 아닙니다."
	model = instance
	_sanitize(model)
	viewport.add_child(model)
	bounds = measure(model)
	frame(bounds)
	return ""

func clear_model() -> void:
	if is_instance_valid(model):
		model.free()
	model = null

func _sanitize(node: Node) -> void:
	# 미리보기에서 원본 씬의 게임 로직과 충돌을 실행하지 않는다.
	node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is Camera3D:
		node.current = false
	if node is GeometryInstance3D:
		node.visibility_range_begin = 0.0
		node.visibility_range_end = 0.0
	for child in node.get_children():
		_sanitize(child)

func measure(node: Node) -> AABB:
	var found := false
	var box := AABB()
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D or current is MultiMeshInstance3D:
			var local: AABB = current.get_aabb()
			var world: AABB = current.global_transform * local
			if world.size.length_squared() > 0.0:
				box = box.merge(world) if found else world
				found = true
		elif current is CollisionShape3D and current.shape != null:
			var shape_box: AABB = current.global_transform * current.shape.get_debug_mesh().get_aabb()
			box = box.merge(shape_box) if found else shape_box
			found = true
		pending.append_array(current.get_children())
	return box

func frame(box: AABB) -> void:
	target = box.get_center()
	var aspect := maxf(0.1, size.x / maxf(size.y, 1.0))
	var half_angle := atan(tan(deg_to_rad(camera.fov * 0.5)) * minf(aspect, 1.0))
	distance = maxf(2.0, box.size.length() * 0.6 / sin(half_angle))
	_update_camera()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_dragging = false
	if auto_rotate:
		yaw += delta * 0.22
	_update_camera()

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.25, distance / 1.15)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(100000.0, distance * 1.15)
	if event is InputEventMouseMotion and _dragging:
		if event.shift_pressed:
			target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * distance * 0.0015
		else:
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.008, -1.45, 1.45)
	accept_event()

func _update_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.near = maxf(0.01, distance / 10000.0)
	camera.far = maxf(1000.0, distance * 5.0 + bounds.size.length() * 2.0)
	camera.look_at(target, Vector3.UP)
