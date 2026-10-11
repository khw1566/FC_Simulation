extends CharacterBody3D
## 저장된 충돌체 위에서 비행한다. 고도 조회나 지형 보정을 하지 않는다.
var camera: Camera3D
var home := Transform3D.IDENTITY

func _ready() -> void:
	camera = get_node("Camera3D")
	home = transform

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode==KEY_R:
			transform = home
			camera.rotation = Vector3.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x*0.003)
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.003,-1.5,1.5)

func _physics_process(_delta: float) -> void:
	if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		velocity = Vector3.ZERO
		return
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	velocity = camera.global_basis*direction.normalized()*(120.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 20.0)
	move_and_slide()
