extends RefCounted
class_name RailwayAssetPathFitter

## 원본 교량을 복제하여 +Z 길이를 실제 궤도 선형에 맞춘다.
const Route = preload("res://scripts/terrain/railway_route.gd")

func place(parent: Node3D, asset_path: String, points: PackedVector3Array, terrain: Node3D, lateral: float = 0.0, width_scale: float = 1.0, options: Dictionary = {}) -> void:
	var packed := load(asset_path) as PackedScene
	if packed == null or points.size()<2:
		return
	var model := packed.instantiate() as Node3D
	var route := Route.new()
	route.configure(points,[])
	var length: float = model.get_meta("length_m",1.0)
	for child in model.get_children():
		if child is MeshInstance3D:
			var excluded: Array = ["bed","rails","sleepers","wires","metal","insulator"]
			if options.get("tunnel",false):
				excluded.append_array(["ballast","ballast_detail"])
			if str(child.name) in excluded:
				child.free()
				continue
			var mesh := ArrayMesh.new()
			var support_bottom: float = (child.transform * child.mesh.get_aabb().position).y
			for surface in range(child.mesh.get_surface_count()):
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
				for i in range(vertices.size()):
					var local: Vector3 = child.transform * vertices[i]
					var pose: Transform3D = route.sample(clampf(local.z/length,0,1)*route.length)
					var side := -pose.basis.x
					var world := pose.origin+side*(local.x*width_scale+lateral)
					var y := local.y
					# 상판·거더·아치는 보존하고 교각 하부만 지표까지 연장한다.
					if str(child.name)=="structure" and y < -2.7 and support_bottom < -2.7 and terrain and not options.get("tunnel",false):
						var ground: float = terrain.get_terrain_elevation(world.x,world.z)
						var target_bottom := minf(ground-pose.origin.y-1.0,-2.8)
						y = lerpf(-2.7,target_bottom,clampf((y+2.7)/(support_bottom+2.7),0.0,1.0))
					vertices[i] = world+Vector3.UP*y
					if i<normals.size():
						normals[i] = Basis(side,Vector3.UP,-pose.basis.z)*normals[i]
				arrays[Mesh.ARRAY_VERTEX] = vertices
				arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = null
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var corrected := ArrayMesh.new()
			for surface in mesh.get_surface_count():
				var normals_builder := SurfaceTool.new()
				normals_builder.create_from(mesh,surface)
				normals_builder.generate_normals()
				normals_builder.commit(corrected)
			mesh = corrected
			child.mesh = mesh
			for old_collision in child.get_children():
				if old_collision is StaticBody3D:
					old_collision.free()
			child.transform = Transform3D.IDENTITY
			child.visibility_range_end = 16000.0
			if str(child.name)=="deck" or (options.get("tunnel",false) and str(child.name) in ["lining","walkway"]):
				var body := StaticBody3D.new()
				var shape := CollisionShape3D.new()
				shape.shape = mesh.create_trimesh_shape()
				body.add_child(shape)
				model.add_child(body)
		else:
			# 원본 직선 충돌과 마커는 변형한 곡선 교량에 사용할 수 없다.
			child.free()
	parent.add_child(model)
