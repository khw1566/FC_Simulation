extends RefCounted
## 원거리 발광 표시와 근거리 실제 광원만 담당한다.

const Route = preload("res://scripts/terrain/railway_route.gd")
const SETTINGS_PATH := "res://assets/generated/railway/night_lighting.json"
static var settings: Dictionary = {}

static func options() -> Dictionary:
	if settings.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if data is Dictionary:
			settings = data
	return settings

static func emission_material(color: Color, power: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = power
	material.roughness = 0.55
	return material

## 같은 색·크기의 표시 재질과 그라디언트 텍스처를 공유한다. 청크·열차마다 새로 만들면 텍스처 생성과 재질 전환이 늘어난다.
static var _marker_materials: Dictionary = {}

static func marker_material(color: Color, _diameter: float, pixels: float) -> StandardMaterial3D:
	var key := "%s|%.3f" % [color.to_html(), pixels]
	if not _marker_materials.has(key):
		_marker_materials[key] = _new_marker_material(color, pixels)
	return _marker_materials[key]

static func _new_marker_material(color: Color, pixels: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.set_flag(BaseMaterial3D.FLAG_FIXED_SIZE, true)
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	material.albedo_texture = texture
	material.set_meta("marker_size", pixels * 0.0015)
	return material

static func beacon(parent: Node3D, at: Vector3, material: StandardMaterial3D, distance: float, label: String) -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * float(material.get_meta("marker_size"))
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.extra_cull_margin = 32.0
	node.visibility_range_end = distance
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func train_car(car: Node3D, profile: Dictionary, index: int, length: float, direction: float, body_center: float) -> void:
	var config := options()
	var last := int(profile.cars) - 1
	var head := index == 0 or index == last
	var group := Node3D.new()
	group.name = "NightLighting"
	car.add_child(group)
	var visibility := float(config.get("train_marker_visibility_m", 6000.0))
	if head:
		var leading := index == 0
		var color := Color(1.0, 0.94, 0.75) if leading else Color(1.0, 0.055, 0.025)
		var material := marker_material(color, 0.5, float(config.get("train_headlight_min_pixels", 3.0)))
		var z := direction * (length * 0.5 + 0.025)
		for side in [-0.9, 0.9]:
			beacon(group, Vector3(side, 1.65, z), material, visibility, "Headlamp" if leading else "TailLamp")
		if leading:
			var spot := SpotLight3D.new()
			spot.name = "HeadlightBeam"
			spot.position = Vector3(0, 1.8, z)
			spot.rotation.x = -0.04
			spot.light_color = color
			spot.light_energy = 3.5
			spot.spot_range = float(config.get("train_headlight_range_m", 110.0))
			spot.spot_angle = 32.0
			spot.shadow_enabled = false
			spot.distance_fade_enabled = true
			spot.distance_fade_begin = float(config.get("train_headlight_fade_begin_m", 180.0))
			spot.distance_fade_length = float(config.get("train_headlight_fade_end_m", 320.0)) - spot.distance_fade_begin
			group.add_child(spot)
		else:
			omni(group, Vector3(0, 1.65, z), color, 0.5, 4.0, 60.0, 100.0, "TailLightGlow")
	var passenger := not (str(profile.id) == "ktx" and head)
	if passenger:
		var cabin := marker_material(Color(1.0, 0.80, 0.45, 0.55), 0.28, float(config.get("train_cabin_min_pixels", 1.5)))
		for side in [-1.0, 1.0]:
			beacon(group, Vector3(side * 1.49, 2.75, body_center), cabin, visibility, "CabinMarker")
		if index % 3 == 1:
			omni(group, Vector3(0, 2.8, body_center), Color(1.0, 0.84, 0.60), 0.35, 4.5, 45.0, 80.0, "CabinLight")

static func track(root: Node3D, route, view_distance: float, lateral: float = 2.45, marker_height: float = 4.95) -> void:
	var config := options()
	var interval := float(config.get("track_marker_spacing_m", 120.0))
	var group := Node3D.new()
	group.name = "RailwayNightMarkers"
	root.add_child(group)
	var material := marker_material(Color(0.52, 0.46, 0.32, float(config.get("track_marker_opacity", 0.6))),
		float(config.get("track_marker_diameter_m", 0.45)), float(config.get("track_marker_min_pixels", 2.0)))
	for i in range(maxi(1, int(ceil(route.length / interval)))):
		for side in [-1.0 if i % 2 == 0 else 1.0]:
			var pose: Transform3D = route.sample(i * interval, side * lateral)
			beacon(group, pose.origin + Vector3.UP * marker_height, material, view_distance, "RailMarker")
	var light_interval := float(config.get("track_light_spacing_m", 300.0))
	for i in range(maxi(1, int(ceil(route.length / light_interval)))):
		var pose: Transform3D = route.sample(i * light_interval, lateral)
		omni(root, pose.origin + Vector3.UP * marker_height, Color(1.0, 0.85, 0.58), float(config.get("track_light_energy", 0.35)),
			float(config.get("track_light_range_m", 6.0)), float(config.get("track_light_fade_begin_m", 60.0)),
			float(config.get("track_light_fade_end_m", 110.0)), "RailwayLocalLight")

static func structure(root: Node3D, length: float, lateral: float, height: float) -> void:
	var route := Route.new()
	route.configure(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, length)]), [])
	track(root, route, 12000.0, lateral, height)

static func omni(parent: Node3D, at: Vector3, color: Color, energy: float, radius: float, fade_begin: float, fade_end: float, label: String) -> void:
	var light := OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = fade_begin
	light.distance_fade_length = maxf(1.0, fade_end - fade_begin)
	parent.add_child(light)
