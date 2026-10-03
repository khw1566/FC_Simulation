extends RefCounted
## 석재 보도와 중앙 유리 난간이 있는 선바위교 근사 에셋.

const Parts = preload("res://scripts/terrain/pedestrian_bridge_geometry.gd")

static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(spec.id)
	var g := Parts.new()
	var length := float(spec.length_m)
	var width := float(spec.width_m)
	var top := float(spec.deck_height_m)
	var spans := int(spec.spans)
	g.box(Vector3(0, top - 0.45, 0), Vector3(width, 0.9, length), "deck")
	for x in [-width * 0.34, 0.0, width * 0.34]:
		g.box(Vector3(x, top - 1.35, 0), Vector3(0.65, 1.5, length))
	for i in range(1, spans):
		var z := -length * 0.5 + length * i / spans
		for x in [-width * 0.28, width * 0.28]:
			g.box(Vector3(x, (top - 2.0) * 0.5, z), Vector3(1.8, top - 2.0, 2.4))
		g.box(Vector3(0, top - 2.0, z), Vector3(width * 0.82, 0.8, 2.8))
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 - 1.4)
		g.box(Vector3(x, top + 0.12, 0), Vector3(2.6, 0.24, length), "paving")
		g.box(Vector3(side * (width * 0.5 - 2.85), top + 0.12, 0), Vector3(0.22, 0.24, length))
		# 석재 포장 줄눈 및 난간 구간.
		for i in range(int(length / 2.0)):
			g.box(Vector3(x, top + 0.245, -length * 0.5 + i * 2.0), Vector3(2.5, 0.012, 0.025), "structure")
		var rail_x: float = side * (width * 0.5 - 0.12)
		for section in range(5):
			var z0 := -length * 0.5 + length * section / 5.0
			var z1 := -length * 0.5 + length * (section + 1) / 5.0
			g.rail(Vector3(rail_x, top + 0.24, z0), Vector3(rail_x, top + 0.24, z1), 1.2, section == 2)
		for z in [-length * 0.35, 0.0, length * 0.35]:
			g.beam(Vector3(x, top + 0.24, z), Vector3(x, top + 5.0, z), 0.12, 0.12, "metal")
			g.box(Vector3(x - side * 1.2, top + 5.0, z), Vector3(2.4, 0.12, 0.3), "metal")
	for z in range(int(-length * 0.5 + 3), int(length * 0.5 - 3), 6):
		for x in [-4.6, 4.6]:
			g.box(Vector3(x, top + 0.012, z), Vector3(0.12, 0.024, 3.0), "markings")
	for x in [-0.12, 0.12]:
		g.box(Vector3(x, top + 0.014, 0), Vector3(0.10, 0.025, length), "yellow")
	for side in [-1.0, 1.0]:
		g.box(Vector3(side * (width * 0.5 - 3.1), top + 0.012, 0), Vector3(0.12, 0.024, length), "markings")
	for end in [-1.0, 1.0]:
		g.box(Vector3(0, (top - 0.9) * 0.5, end * (length * 0.5 - 0.8)), Vector3(width, top - 0.9, 1.6))
	g.finish(root)
	Parts.marker(root, "RoadA", Vector3(0, top, -length * 0.5))
	Parts.marker(root, "RoadB", Vector3(0, top, length * 0.5))
	return root
