extends SceneTree

const Track = preload("res://scripts/terrain/railway_track_builder.gd")
const Fitter = preload("res://scripts/terrain/railway_asset_path_fitter.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture_script = load(get_script().resource_path.get_base_dir().path_join("rail_support_fixture.gd"))
	var terrain = fixture_script.new()
	var points := PackedVector3Array([Vector3(0,20,0),Vector3(0,20,32)])
	var track := Track.build(points,{"track_bed":"ballast"},{"bridge":true},12000,terrain)
	var failures: Array[String] = []
	var checked := 0
	for node in track.get_children():
		if node is MultiMeshInstance3D and node.multimesh.mesh.size == Vector3(1.4,1,1.4):
			for index in node.multimesh.instance_count:
				var pose: Transform3D = node.multimesh.get_instance_transform(index)
				var bottom := (pose*Vector3(0,-0.5,0)+track.position).y
				print("SUPPORT ",pose," bottom=",bottom)
				if absf(bottom+36.0)>0.01:
					failures.append("일반 교각 지표 연결 실패")
				checked += 1
	var parent := Node3D.new()
	Fitter.new().place(parent,"res://assets/generated/railway_bridges/rail_plate_girder.scn",points,terrain)
	if parent.get_child_count() == 0:
		failures.append("교량 에셋 미배치")
	else:
		for node in parent.get_child(0).get_children():
			if node is MeshInstance3D and node.name == "structure":
				if absf(node.mesh.get_aabb().position.y+36.0)>0.01:
					failures.append("에셋 교각 지표 연결 실패")
				checked += 1
			if node is MeshInstance3D and node.name == "deck":
				if absf(node.mesh.get_aabb().position.y-18.95)>0.01:
					failures.append("상판 높이 변형")
	if checked<2:
		failures.append("교각 검증 누락")
	parent.free()
	track.free()
	terrain.free()
	print(JSON.stringify({"checked_supports":checked,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
