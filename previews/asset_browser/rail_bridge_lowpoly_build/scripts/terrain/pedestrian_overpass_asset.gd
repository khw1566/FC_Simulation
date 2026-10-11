extends RefCounted
## 양쪽 직선 계단과 난간을 갖춘 범용 육교.

const Lighting = preload("res://scripts/core/asset_marker_lighting.gd")
const Parts = preload("res://scripts/terrain/pedestrian_bridge_geometry.gd")

static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(spec.id)
	var g := Parts.new()
	var length := float(spec.length_m)
	var width := float(spec.width_m)
	var top := float(spec.deck_height_m)
	var run := float(spec.stair_run_m)
	var steps := int(spec.step_count)
	g.box(Vector3(0, top - 0.3, 0), Vector3(width, 0.6, length), "deck")
	for side in [-1.0, 1.0]:
		g.box(Vector3(side * (width * 0.5 - 0.15), top - 0.65, 0), Vector3(0.22, 0.8, length), "metal")
		g.rail(Vector3(side * width * 0.5, top, -length * 0.5), Vector3(side * width * 0.5, top, length * 0.5))
	for end in [-1.0, 1.0]:
		var z: float = end * (length * 0.5 - 1.0)
		g.box(Vector3(0, (top - 0.6) * 0.5, z), Vector3(1.2, top - 0.6, 1.5))
		g.box(Vector3(0, 0.12, z), Vector3(2.4, 0.24, 2.4))
		for i in range(steps):
			var height := top * (steps - i) / steps
			var step_z: float = end * (length * 0.5 + (i + 0.5) * run / steps)
			g.box(Vector3(0, height - 0.12, step_z), Vector3(width, 0.24, run / steps + 0.01), "deck")
			g.box(Vector3(0, height + 0.005, step_z - end * run / steps * 0.42), Vector3(width - 0.1, 0.01, 0.04), "markings")
		for side in [-1.0, 1.0]:
			var a := Vector3(side * (width * 0.5 - 0.15), top - 0.4, end * length * 0.5)
			var b := Vector3(a.x, 0.08, end * (length * 0.5 + run))
			g.beam(a, b, 0.22, 0.45, "metal")
			g.rail(a + Vector3.UP * 0.4, b + Vector3.UP * 0.15)
		g.box(Vector3(0, 0.12, end * (length * 0.5 + run + 0.7)), Vector3(width, 0.24, 1.4), "deck")
	g.finish(root)
	var light_points := PackedVector3Array()
	var lamp_count := maxi(2, int(ceil(length / 120.0)) + 1)
	for i in range(lamp_count):
		light_points.append(Vector3(width * 0.44, top + 0.8, -length * 0.5 + length * i / (lamp_count - 1)))
	Lighting.bridge(root, light_points)
	Parts.marker(root, "EntranceA", Vector3(0, 0.24, -length * 0.5 - run - 1.4))
	Parts.marker(root, "EntranceB", Vector3(0, 0.24, length * 0.5 + run + 1.4))
	return root
