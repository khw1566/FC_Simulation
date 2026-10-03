extends RefCounted
## 좁은 콘크리트 보행판과 수로가 있는 낮은 징검다리.

const Parts = preload("res://scripts/terrain/pedestrian_bridge_geometry.gd")

static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(spec.id)
	var g := Parts.new()
	var length := float(spec.length_m)
	var width := float(spec.width_m)
	var top := float(spec.deck_height_m)
	var count := maxi(1, int(ceil(length / float(spec.segment_m))))
	var spacing := length / count
	for i in range(count):
		var z := -length * 0.5 + (i + 0.5) * spacing
		# 개별 콘크리트 상판 아래에 반복 수로와 넓은 하부 받침을 표현한다.
		g.box(Vector3(0, top - 0.14, z), Vector3(width, 0.28, spacing - 0.035), "stone")
		g.box(Vector3(0, top * 0.5 - 0.12, z), Vector3(width * 0.85, top - 0.25, 0.48))
		g.box(Vector3(0, -0.18, z), Vector3(2.6, 0.35, spacing - 0.12))
	for end in [-1.0, 1.0]:
		g.box(Vector3(0, top - 0.15, end * (length * 0.5 + 0.75)), Vector3(2.2, 0.3, 1.5), "stone")
	g.finish(root)
	Parts.marker(root, "BankA", Vector3(0, top, -length * 0.5))
	Parts.marker(root, "BankB", Vector3(0, top, length * 0.5))
	return root
