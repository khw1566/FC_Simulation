extends SceneTree
## 건물 높이와 중정 면적을 메시 결과로 검증한다.
const Builder = preload("res://scripts/terrain/building_mesh_builder.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var triangles: Array = []
	for rect in [Rect2(0,0,3,10),Rect2(7,0,3,10),Rect2(3,0,4,3),Rect2(3,7,4,3)]:
		var a: Vector2 = rect.position
		var b := Vector2(rect.end.x,rect.position.y)
		var c: Vector2 = rect.end
		var d := Vector2(rect.position.x,rect.end.y)
		triangles.append([[a.x,a.y],[b.x,b.y],[c.x,c.y]])
		triangles.append([[a.x,a.y],[c.x,c.y],[d.x,d.y]])
	var fixture := Node3D.new()
	root.add_child(fixture)
	var material := StandardMaterial3D.new()
	Builder.build_chunk_buildings_mesh([{"polygon":[[0,0],[10,0],[10,10],[0,10]],"center":[5,0,5],"height":10,"height_source":"osm_height","base_y":0,"holes":[[[3,3],[7,3],[7,7],[3,7]]],"roof_triangles":triangles}],fixture,material,func(_x,_z,_fallback):return 0.0)
	var area := 0.0
	for mesh in fixture.find_children("*","MeshInstance3D",true,false):
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0,vertices.size(),3):
			if is_equal_approx(vertices[i].y,10) and is_equal_approx(vertices[i+1].y,10) and is_equal_approx(vertices[i+2].y,10):
				area += (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length()/2
	var checks := {"중정_제외_지붕면적_84m2":absf(area-84)<.01}
	fixture.free()
	var output := FileAccess.open("res://../results/261003_kanmon_building_mesh_validation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":not checks.values().has(false),"checks":checks,"roof_area":area},"  "))
	print(JSON.stringify(checks))
	quit(0 if not checks.values().has(false) else 1)

