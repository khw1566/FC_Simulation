extends RefCounted
class_name RailwayTrainBuilder

const NightLighting = preload("res://scripts/terrain/railway_night_lighting.gd")

static var model_scenes: Dictionary = {}

static func build(profile: Dictionary) -> Node3D:
	var cache_key := JSON.stringify(profile)
	if model_scenes.has(cache_key):
		return model_scenes[cache_key].instantiate()
	var train := Node3D.new()
	train.name = str(profile.id) + "_train"
	var body := _material(profile.body_color)
	var stripe := _material(profile.stripe_color)
	var glass := NightLighting.emission_material(Color(0.28, 0.24, 0.17), float(NightLighting.options().get("window_emission_energy", 0.75)))
	var cockpit_glass := _material([0.045, 0.065, 0.085])
	var dark := _material([0.14, 0.15, 0.16])
	var red := _material([0.66, 0.10, 0.15])
	var light := _material([0.95, 0.92, 0.72])
	light.emission_enabled = true
	light.emission = light.albedo_color
	for index in int(profile.cars):
		var car := Node3D.new()
		car.name = "Car_%02d" % index
		train.add_child(car)
		var length: float = float(profile.car_length_m)
		var head: bool = index == 0 or index == int(profile.cars) - 1
		var ktx: bool = profile.id == "ktx"
		if ktx and head:
			length = float(profile.get("power_car_length_m", length))
		var direction: float = -1.0 if index == 0 else 1.0
		var lamp := light if index == 0 else NightLighting.emission_material(Color(1.0, 0.055, 0.025), 2.0)
		var body_center: float = -direction * 2.25 if ktx and head else 0.0
		_box(car, Vector3(2.9, 2.8, length - (4.5 if ktx and head else 0.4)), Vector3(0, 2.2, body_center), body)
		_box(car, Vector3(2.94, 0.38, length - (4.5 if ktx and head else 0.5)), Vector3(0, 1.85, body_center), stripe)
		if not ktx:
			_box(car, Vector3(2.945, 0.08, length - 0.5), Vector3(0, 2.08, 0), red)
		_box(car, Vector3(2.8, 0.18, length - (4.5 if ktx and head else 0.8)), Vector3(0, 3.69, body_center), dark)
		for side in [-1.0, 1.0]:
			if ktx and head:
				for vent in range(10):
					_box(car, Vector3(0.035, 1.0, 0.20), Vector3(side * 1.46, 2.55, body_center - 3.0 + vent * 0.5), dark)
			else:
				for window in range(8):
					_box(car, Vector3(0.035, 0.68, 1.2), Vector3(side * 1.46, 2.75, -length * 0.36 + window * length * 0.1), glass)
			if not ktx:
				for door in [-0.32, 0.0, 0.32]:
					_box(car, Vector3(0.045, 2.05, 1.15), Vector3(side * 1.48, 2.0, door * length), body)
					_box(car, Vector3(0.055, 0.55, 0.65), Vector3(side * 1.49, 2.65, door * length), glass)
		for bogie in [-0.32, 0.32]:
			_box(car, Vector3(2.1, 0.45, 2.0), Vector3(0, 0.55, bogie * length), dark)
			for axle in [-0.65, 0.65]:
				for side in [-1.0, 1.0]:
					var wheel := CylinderMesh.new()
					wheel.top_radius = 0.42
					wheel.bottom_radius = 0.42
					wheel.height = 0.18
					wheel.radial_segments = 10
					var instance := _mesh(car, wheel, Vector3(side * 1.03, 0.45, bogie * length + axle), dark)
					instance.rotation.z = PI / 2.0
		if head:
			if ktx:
				_nose(car, length, direction, body)
				_box(car, Vector3(1.65, 0.45, 0.05), Vector3(0, 1.35, direction * length * 0.5), stripe)
			var front_z: float = direction * (length * 0.5 - 0.08)
			if ktx:
				var windshield := BoxMesh.new()
				windshield.size = Vector3(2.0, 0.65, 0.05)
				var window := _mesh(car, windshield, Vector3(0, 3.23, direction * (length * 0.5 - 3.4)), cockpit_glass)
				window.rotation.x = direction * deg_to_rad(67.0)
			else:
				_box(car, Vector3(2.25, 0.7, 0.06), Vector3(0, 2.9, front_z), cockpit_glass)
			for side in [-0.9, 0.9]:
				_box(car, Vector3(0.25, 0.15, 0.08), Vector3(side, 1.65, front_z + direction * 0.07), lamp)
		NightLighting.train_car(car, profile, index, length, direction, body_center)
		if index == 1 or (ktx and index == int(profile.cars) - 2):
			_box(car, Vector3(0.08, 0.6, 0.08), Vector3(0, 4.02, 0), dark)
			_box(car, Vector3(1.3, 0.05, 0.12), Vector3(0, 4.35, 0), dark)
	_set_owners(train, train)
	var packed := PackedScene.new()
	packed.pack(train)
	model_scenes[cache_key] = packed
	return train

static func _set_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owners(child, root)

static func _nose(parent: Node3D, length: float, direction: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back: float = direction * (length * 0.5 - 4.5)
	var tip: float = direction * length * 0.5
	var vertices := [Vector3(-1.45, 0.8, back), Vector3(1.45, 0.8, back), Vector3(-1.45, 3.6, back), Vector3(1.45, 3.6, back), Vector3(-0.9, 0.8, tip), Vector3(0.9, 0.8, tip), Vector3(-0.85, 1.8, tip), Vector3(0.85, 1.8, tip)]
	for triangle in [[0,4,6], [0,6,2], [1,3,7], [1,7,5], [2,6,7], [2,7,3], [4,5,7], [4,7,6]]:
		for index in triangle:
			st.add_vertex(vertices[index])
	st.generate_normals()
	var nose_material := material.duplicate() as StandardMaterial3D
	nose_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(parent, st.commit(), Vector3.ZERO, nose_material)

static func _material(rgb: Array) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(rgb[0], rgb[1], rgb[2])
	material.roughness = 0.6
	return material

static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(parent, mesh, at, material)

static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.visibility_range_end = 6000.0
	parent.add_child(instance)
	return instance
