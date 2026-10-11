extends SceneTree

const Architecture = preload("res://scripts/terrain/campus_architecture_builder.gd")
const RuntimeManager = preload("res://scripts/terrain/building_road_manager.gd")

func _initialize() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var rotated_boxes: Array = []
	Architecture._box(rotated_boxes, Vector3.ZERO, Vector3(40,0.7,0.24),0.7)
	assert(is_equal_approx(rotated_boxes[0].basis.x.length(),40.0), "회전 후 난간 길이 변경")
	assert(is_equal_approx(rotated_boxes[0].basis.z.length(),0.24), "회전 후 난간 두께 변경")
	# 오목한 윤곽에서 옥상 설비가 빈 공간에 생성되지 않는지 검증한다.
	var ring := PackedVector2Array([Vector2(0,0),Vector2(40,0),Vector2(40,10),Vector2(10,10),Vector2(10,40),Vector2(0,40)])
	Architecture.build(holder, ring, 12.0, 24.0, func(x: float,z: float,_fallback: float): return 10.0+x*0.02+z*0.01)
	var pad_count := 0
	var window_count := 0
	for child in holder.get_children():
		if child is MeshInstance3D:
			pad_count += 1
			assert(child.get_child_count() > 0, "포장부지 충돌체 누락")
			var vertices: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				assert(vertex.is_finite(), "유효하지 않은 부지 좌표")
		if child is MultiMeshInstance3D:
			assert(child.name != "Campus_roof", "오목 윤곽 밖 옥상 설비")
			if child.name == "Campus_windows":
				window_count = child.multimesh.instance_count
	assert(pad_count == 1 and window_count > 0)
	print("CAMPUS_GEOMETRY_CHECK=PASS windows=",window_count)
	quit()
