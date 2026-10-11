extends Node3D
## 작은 발광 장치와 근거리 광원으로만 에셋을 식별한다.
@export var vessel_length := 0.0
@export var vessel_beam := 0.0
@export var vessel_deck := 0.0
@export var vessel_kind := ""

func _ready() -> void:
	if vessel_length > 0.0 and get_child_count() == 0:
		vessel(self, vessel_length, vessel_beam, vessel_deck, vessel_kind)

static func vessel(parent: Node3D, length: float, beam: float, deck: float, kind: String = "") -> void:
	var radius := clampf(beam * 0.01, 0.10, 0.25)
	# 좌현 적색·우현 녹색·선미 백색. 물리 크기로 표시하며 원거리 확대는 없다.
	lamp(parent, Vector3(-beam * 0.48, deck + 1.0, length * 0.18), Color(0.8, 0.04, 0.025), radius)
	lamp(parent, Vector3(beam * 0.48, deck + 1.0, length * 0.18), Color(0.04, 0.65, 0.13), radius)
	lamp(parent, Vector3(0, deck + 0.5, length * 0.46), Color(0.75, 0.72, 0.60), radius)
	var mast := Vector3(0, deck + 15.0, length * 0.34)
	if length < 40.0:
		mast = Vector3(0, deck + 9.5, -2.0)
	if kind == "motor_boat":
		mast = Vector3(0, deck + 3.2, -0.7)
	elif kind == "fishing_boat":
		mast = Vector3(0, deck + 5.1, -3.0)
	lamp(parent, mast, Color(0.8, 0.76, 0.64), radius)
	local_light(parent, Vector3(beam * 0.35, deck + 1.0, length * 0.35), minf(5.0, beam * 0.7))

static func bridge(parent: Node3D, points: PackedVector3Array) -> void:
	var group := Node3D.new()
	group.name = "BridgeLighting"
	parent.add_child(group)
	for point in points:
		lamp(group, point, Color(0.62, 0.55, 0.39), 0.10)
	if not points.is_empty():
		local_light(group, points[points.size() / 2], 4.0)

static func lamp(parent: Node3D, at: Vector3, color: Color, radius: float) -> void:
	var node := MeshInstance3D.new()
	node.name = "SmallMarkerLamp"
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	material.roughness = 1.0
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.visibility_range_end = 2500.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func local_light(parent: Node3D, at: Vector3, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = "SoftLocalLight"
	light.position = at
	light.light_color = Color(1.0, 0.85, 0.65)
	light.light_energy = 0.2
	light.omni_range = maxf(1.0, radius)
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 50.0
	parent.add_child(light)
