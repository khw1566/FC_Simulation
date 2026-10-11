extends RefCounted
## 독립 철도 교량 1개를 정적 모델로 조립한다.

const Parts = preload("res://scripts/terrain/railway_bridge_geometry.gd")
const Structures = preload("res://scripts/terrain/railway_bridge_structures.gd")

static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(spec.id)
	var g := Parts.new()
	Structures.build(g, spec)
	g.tracks(spec)
	if str(spec.kind) != "station":
		g.parapets(float(spec.length_m), float(spec.width_m))
	if bool(spec.get("include_end_support", true)):
		g.pier(float(spec.length_m), float(spec.width_m), float(spec.pier_height_m))
	g.finish(root, spec)
	root.set_meta("label_ko", spec.name_ko)
	root.set_meta("kind", spec.kind)
	root.set_meta("accuracy", spec.get("accuracy", "게임용 범용 교량, 치수는 제작 설정값"))
	return root
