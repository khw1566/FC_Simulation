extends RefCounted
class_name HeritageModelBuilder

const Geometry = preload("res://scripts/terrain/heritage_mesh_builder.gd")

func build(spec: Dictionary) -> Node3D:
	var mesh := Geometry.new()
	for wall in spec.walls:
		var points: Array = wall.points
		for i in range(points.size() - 1):
			mesh.wall(Vector2(points[i][0], points[i][1]), Vector2(points[i + 1][0], points[i + 1][1]), float(wall.height), float(wall.width), bool(wall.get("ruined", false)))
	if spec.has("gate"):
		_gate(mesh, Vector3(float(spec.gate.x), 0, float(spec.gate.z)))
	return mesh.finish(str(spec.id))

func _gate(mesh, origin: Vector3) -> void:
	# 독립 기둥식 개거식 문루: 가운데 통행 공간을 열어 둔다.
	for x in [-6.0, -2.0, 2.0, 6.0]:
		for z in [-3.2, 0.0, 3.2]:
			mesh.box("gate_stone", origin + Vector3(x, 0.2, z), Vector3(1.05, 1.0, 1.05))
			mesh.box("gate_wood", origin + Vector3(x, 2.2, z), Vector3(0.46, 4.3, 0.46))
	mesh.box("gate_wood", origin + Vector3(0, 4.2, 0), Vector3(13.2, 0.45, 7.4))
	for y in [3.7, 7.3]:
		for z in [-3.2, 3.2]:
			mesh.box("gate_green", origin + Vector3(0, y, z), Vector3(13, 0.32, 0.4))
		for x in [-6.0, -2.0, 2.0, 6.0]:
			mesh.box("gate_green", origin + Vector3(x, y + 0.3, 0), Vector3(0.34, 0.25, 8.1))
	for x in [-5.5, -1.85, 1.85, 5.5]:
		for z in [-2.7, 2.7]:
			mesh.box("gate_wood", origin + Vector3(x, 5.9, z), Vector3(0.36, 3.0, 0.36))
	for z in [-3.0, 3.0]:
		for i in range(7):
			mesh.box("gate_wood", origin + Vector3(-5.8 + i * 1.93, 4.9, z), Vector3(0.09, 0.85, 0.09))
		mesh.box("gate_wood", origin + Vector3(0, 5.3, z), Vector3(12.2, 0.12, 0.16))
	mesh.roof(origin + Vector3(0, 4.4, 0), 17.0, 11.5, 1.45)
	mesh.roof(origin + Vector3(0, 7.5, 0), 15.5, 10.3, 2.5)
	# 뒤쪽 누마루 접근 계단.
	for i in range(18):
		var y := float(i + 1) * 4.2 / 18
		mesh.box("gate_stone", origin + Vector3(8.7, y / 2 - 0.25, -9 + i * 0.42), Vector3(2.1, y + 0.5, 0.43))
