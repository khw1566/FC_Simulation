extends RefCounted
## 단독 입구·내부·출구와 연결 완료 터널을 조립한다.

const Parts = preload("res://scripts/terrain/railway_tunnel_geometry.gd")
const Details = preload("res://scripts/terrain/railway_tunnel_details.gd")
const NightLighting = preload("res://scripts/terrain/railway_night_lighting.gd")

static func part_spec(profile: Dictionary, part: String) -> Dictionary:
	var spec := profile.duplicate(true)
	spec.part = part
	spec.id = str(profile.id) + "_tunnel_" + part
	spec.length_m = spec.body_length_m if part == "body" else spec.portal_length_m
	spec.name_ko = str(profile.name_ko) + {"entry": " 입구", "body": " 반복 내부 구간", "exit": " 출구"}[part]
	return spec

static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(spec.id)
	var g := Parts.new()
	g.lining(spec)
	Details.build(g, spec)
	g.finish(root)
	NightLighting.structure(root, float(spec.length_m), float(spec.inner_half_width_m) - 0.25, 2.55)
	_markers(root, spec, float(spec.length_m))
	root.set_meta("label_ko", spec.name_ko)
	root.set_meta("track_bed", spec.track_bed)
	root.set_meta("part", spec.part)
	return root

static func assembled(profile: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(profile.id) + "_tunnel_set"
	var parts: Array[String] = ["entry"]
	for _i in range(int(profile.body_count)):
		parts.append("body")
	parts.append("exit")
	var offset := 0.0
	var previous: Node3D
	var joins: Array[Dictionary] = []
	for i in range(parts.size()):
		var spec := part_spec(profile, parts[i])
		var node := build(spec)
		node.name = str(spec.id) + "_%d" % i
		node.position.z = offset
		root.add_child(node)
		if previous != null:
			for track in range(2):
				var a: Vector3 = previous.position + previous.get_node("Track%dEnd" % track).position
				var b: Vector3 = node.position + node.get_node("Track%dStart" % track).position
				assert(a.distance_to(b) < 0.0001, "터널 궤도 연결점 불일치")
			var previous_spec := part_spec(profile, parts[i - 1])
			var prev_g := Parts.new()
			var next_g := Parts.new()
			var end_section: PackedVector2Array = prev_g.section(previous_spec, false, 1.0)
			var start_section: PackedVector2Array = next_g.section(spec, false, 0.0)
			assert(end_section == start_section, "터널 라이닝 접속 단면 불일치")
			joins.append({"from": str(previous.name), "to": str(node.name), "z_m": offset, "gap_m": 0.0})
		previous = node
		offset += float(spec.length_m)
	_markers(root, profile, offset)
	root.set_meta("label_ko", str(profile.name_ko) + " 연결 세트")
	root.set_meta("track_bed", profile.track_bed)
	root.set_meta("connections", joins)
	return root

static func _markers(root: Node3D, spec: Dictionary, length: float) -> void:
	var top := float(spec.rail_top_y_m)
	var spacing := float(spec.track_spacing_m)
	for end in ["Start", "End"]:
		var z: float = 0.0 if end == "Start" else length
		_marker(root, "Track" + end, Vector3(0, top, z))
		for i in range(2):
			_marker(root, "Track%d%s" % [i, end], Vector3((i - 0.5) * spacing, top, z))
	root.set_meta("length_m", length)
	root.set_meta("gauge_m", spec.gauge_m)
	root.set_meta("track_spacing_m", spec.track_spacing_m)
	root.set_meta("rail_top_y_m", top)
	root.set_meta("connection_axis", "+Z")

static func _marker(root: Node3D, label: String, point: Vector3) -> void:
	var node := Marker3D.new()
	node.name = label
	node.position = point
	root.add_child(node)
