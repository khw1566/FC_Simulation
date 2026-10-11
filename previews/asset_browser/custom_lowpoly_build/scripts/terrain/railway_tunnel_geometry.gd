extends RefCounted
## 중공 터널 라이닝 및 재질별 병합 부재를 생성한다.

const BaseGeometry = preload("res://scripts/terrain/bridge_geometry.gd")
var geometry = BaseGeometry.new()

func box(center: Vector3, size: Vector3, group: String) -> void:
	geometry.beam(center - Vector3.UP * size.y * 0.5, center + Vector3.UP * size.y * 0.5, size.x, size.z, group)

func beam(a: Vector3, b: Vector3, width: float, depth: float, group: String) -> void:
	geometry.beam(a, b, width, depth, group)

func section(spec: Dictionary, outer: bool, progress: float) -> PackedVector2Array:
	var flare := 0.0
	if str(spec.part) != "body":
		flare = float(spec.portal_flare_m) * (progress if str(spec.part) == "exit" else 1.0 - progress)
	var thickness := float(spec.shell_thickness_m) if outer else 0.0
	var radius := float(spec.inner_half_width_m) + flare + thickness
	var spring := float(spec.spring_height_m)
	var rise := float(spec.inner_height_m) - spring + flare * 0.65 + thickness
	var floor_y := -0.55 - thickness
	var points := PackedVector2Array([Vector2(-radius, floor_y), Vector2(-radius, spring)])
	var count := int(spec.cross_section_segments)
	for i in range(1, count + 1):
		var angle := PI - PI * i / count
		points.append(Vector2(radius * cos(angle), spring + rise * sin(angle)))
	points.append(Vector2(radius, floor_y))
	return points

func lining(spec: Dictionary) -> void:
	var length := float(spec.length_m)
	var inner_start := section(spec, false, 0.0)
	var inner_end := section(spec, false, 1.0)
	var outer_start := section(spec, true, 0.0)
	var outer_end := section(spec, true, 1.0)
	for i in range(inner_start.size()):
		var j := (i + 1) % inner_start.size()
		var a := Vector3(inner_start[i].x, inner_start[i].y, 0)
		var b := Vector3(inner_start[j].x, inner_start[j].y, 0)
		var c := Vector3(inner_end[j].x, inner_end[j].y, length)
		var d := Vector3(inner_end[i].x, inner_end[i].y, length)
		quad(a, b, c, d, "lining")
		var oa := Vector3(outer_start[i].x, outer_start[i].y, 0)
		var ob := Vector3(outer_start[j].x, outer_start[j].y, 0)
		var oc := Vector3(outer_end[j].x, outer_end[j].y, length)
		var od := Vector3(outer_end[i].x, outer_end[i].y, length)
		quad(oa, od, oc, ob, "lining")
		# 양끝은 중공 단면의 테두리만 닫아 터널 통로를 막지 않는다.
		quad(oa, ob, b, a, "lining")
		quad(od, d, c, oc, "lining")
	var seams := maxi(1, int(ceil(length / float(spec.joint_spacing_m))))
	for index in range(seams):
		var progress := float(index) / seams
		var ring := section(spec, false, progress)
		for i in range(1, ring.size()):
			beam(Vector3(ring[i - 1].x, ring[i - 1].y, progress * length),
				Vector3(ring[i].x, ring[i].y, progress * length), 0.025, 0.025, "joints")

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, group: String) -> void:
	if not geometry.batches.has(group):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		geometry.batches[group] = surface
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, b, c, a, c, d]:
		geometry.batches[group].set_normal(normal)
		geometry.batches[group].add_vertex(point)

func finish(root: Node3D) -> void:
	var palette := {"lining": Color(0.61, 0.62, 0.60), "joints": Color(0.38, 0.39, 0.38),
		"portal": Color(0.71, 0.72, 0.70), "bed": Color(0.56, 0.57, 0.56),
		"ballast": Color(0.32, 0.30, 0.27), "ballast_detail": Color(0.40, 0.39, 0.35),
		"sleepers": Color(0.66, 0.65, 0.61), "rails": Color(0.46, 0.50, 0.53),
		"walkway": Color(0.72, 0.71, 0.66), "drain": Color(0.17, 0.18, 0.17),
		"metal": Color(0.36, 0.40, 0.43), "wires": Color(0.18, 0.19, 0.20),
		"light": Color(0.96, 0.94, 0.82), "marker": Color(0.23, 0.42, 0.31)}
	for group in geometry.batches:
		var instance := MeshInstance3D.new()
		instance.name = str(group)
		instance.mesh = geometry.batches[group].commit()
		var material := StandardMaterial3D.new()
		material.albedo_color = palette.get(group, Color.GRAY)
		material.roughness = 0.88
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if group in ["rails", "metal"]:
			material.metallic = 0.45
		if group in ["light", "marker"]:
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_energy_multiplier = 1.4
		instance.material_override = material
		root.add_child(instance)
		if group in ["lining", "walkway", "bed", "ballast"]:
			instance.create_trimesh_collision()
