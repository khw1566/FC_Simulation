extends Node3D
class_name NuclearBombBody

## 조준점 상공에서 투하된 폭탄이 중력으로 낙하해 폭발 고도에 닿으면 신호를 보낸다.

signal reached_burst_height(bomb: Node)

const GRAVITY := 9.8

var preset: Dictionary
var ground_point := Vector3.ZERO
var burst_y := 0.0
var velocity := Vector3.ZERO
var _start := Vector3.ZERO

func setup(preset_data: Dictionary, ground: Vector3, burst_height_y: float, drop_height: float, drop_speed: float) -> void:
	preset = preset_data
	ground_point = ground
	burst_y = burst_height_y
	_start = Vector3(ground.x, burst_height_y + drop_height, ground.z)
	velocity = Vector3.DOWN * drop_speed
	name = "Bomb_%s" % str(preset_data.id)

func _ready() -> void:
	top_level = true
	global_position = _start
	_build_model()
	_orient()

func _process(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	global_position += velocity * delta
	_orient()
	if global_position.y <= burst_y:
		reached_burst_height.emit(self)
		queue_free()

## 폭발까지 남은 시간(s)
func time_to_burst() -> float:
	var h := global_position.y - burst_y
	var v := -velocity.y
	return (-v + sqrt(maxf(v * v + 2.0 * GRAVITY * h, 0.0))) / GRAVITY

func _orient() -> void:
	if velocity.length_squared() > 0.01:
		var up := Vector3.FORWARD if absf(velocity.normalized().y) > 0.98 else Vector3.UP
		look_at(global_position + velocity, up)

## 원통 동체 + 꼬리날개 4장의 단순 모델(-Z가 진행 방향)
func _build_model() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.22, 0.22)
	material.metallic = 0.6
	material.roughness = 0.45
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 3.2
	body.mesh = capsule
	body.material_override = material
	body.rotation_degrees.x = 90.0
	add_child(body)
	for i in range(4):
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.9, 0.7)
		fin.mesh = box
		fin.material_override = material
		fin.rotation.z = float(i) * PI * 0.5
		fin.position = Vector3(0.0, 0.0, 1.35) + Vector3(cos(float(i) * PI * 0.5 + PI * 0.5), sin(float(i) * PI * 0.5 + PI * 0.5), 0.0) * 0.45
		add_child(fin)
