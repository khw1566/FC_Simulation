extends Node3D
class_name LandmarkBeacon

var landmark_id: String = ""
var landmark_name: String = ""
var target_pos: Vector3 = Vector3.ZERO
var pole_height: float = 100.0

var _label: Label3D
var _line_mesh_instance: MeshInstance3D

func setup(id: String, name: String, pos: Vector3, p_height: float) -> void:
	self.landmark_id = id
	self.landmark_name = name
	self.target_pos = pos
	self.pole_height = p_height
	self.position = pos
	_build_visuals()

func _build_visuals() -> void:
	# 1. 수직 Y축 기둥 라인 (CylinderMesh) - 반투명 네온 광선 비콘
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 2.5
	cylinder.bottom_radius = 2.5
	cylinder.height = pole_height

	_line_mesh_instance = MeshInstance3D.new()
	_line_mesh_instance.mesh = cylinder
	_line_mesh_instance.position.y = pole_height * 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.90)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mesh_instance.material_override = mat
	add_child(_line_mesh_instance)

	# 1-2. 비콘 상단 다이아몬드 마커 (원거리 식별용 큐브 마커)
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(12.0, 12.0, 12.0)
	var marker_inst := MeshInstance3D.new()
	marker_inst.mesh = marker_mesh
	marker_inst.position.y = pole_height + 6.0
	marker_inst.rotation_degrees = Vector3(45.0, 45.0, 0.0)
	marker_inst.material_override = mat
	add_child(marker_inst)

	# 2. 상단 거리 표시 3D 라벨 (원거리에서도 선명하게 보이도록 fixed_size 지원)
	_label = Label3D.new()
	_label.position.y = pole_height + 25.0
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true # 지형 및 건물 뒤에 있어도 가려지지 않고 항상 전면 표시
	_label.fixed_size = true    # 카메라 거리에 따라 글자 크기가 축소되지 않고 일정 픽셀 크기 유지
	_label.pixel_size = 0.002
	_label.font_size = 18
	_label.outline_size = 6
	_label.outline_modulate = Color(0, 0, 0, 1)
	_label.modulate = Color(1, 1, 1, 1)
	_label.text = "%s\n[--- m]" % landmark_name
	add_child(_label)

func update_distance(player_pos: Vector3) -> void:
	if not _label:
		return
	var dist_meters := target_pos.distance_to(player_pos)
	if dist_meters >= 1000.0:
		var dist_km := dist_meters / 1000.0
		_label.text = "%s\n[%.2f km]" % [landmark_name, dist_km]
	else:
		_label.text = "%s\n[%d m]" % [landmark_name, int(dist_meters)]
