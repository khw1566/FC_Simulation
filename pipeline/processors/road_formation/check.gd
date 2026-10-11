extends SceneTree
const Grader = preload("res://scripts/terrain/road_formation_grader.gd")
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")
const Batch = preload("res://scripts/terrain/road_batch_builder.gd")
const RoadMesh = preload("res://scripts/terrain/road_mesh_builder.gd")
const Policy = preload("res://scripts/terrain/road_visibility_policy.gd")
const Host = preload("res://check_host.gd")
var report: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _vertices(arrays_list: Array) -> Dictionary:
	var counts: Dictionary = {}
	for arrays in arrays_list:
		for p in arrays[Mesh.ARRAY_VERTEX]:
			var key := "%.4f,%.4f,%.4f" % [p.x,p.y,p.z]
			counts[key] = int(counts.get(key,0))+1
	return counts

func _run() -> void:
	# 실제 통합 관리자를 생성하지 않고 파싱·의존성만 확인한다.
	assert(load("res://scripts/terrain/terrain_chunk_manager.gd").can_instantiate())
	assert(load("res://scripts/terrain/building_road_manager.gd").can_instantiate())
	var grader := Grader.new()
	grader.configure("res://fixture/source.json")
	assert(grader.enabled)
	var image := Image.create(33,33,false,Image.FORMAT_RF)
	for z in 33:
		for x in 33:
			var wx := float(x)*4.0-64.0
			var wz := float(z)*4.0-64.0
			image.set_pixel(x,z,Color((20.0+wx*.1+wz*.3)/100.0,0,0))
	var ground := func(x,z,_fallback): return grader.corrected_height(Vector3(x,20.0+x*.1+z*.3,z))
	var before_delta := .3*6.0
	var after_delta: float = absf(ground.call(0,-3,0)-ground.call(0,3,0))
	assert(after_delta < .00001)
	assert(absf(ground.call(0,30,0)-29.0)<.00001)
	var request := {"image":image,"grid_res":4,"size":128.0,"center":Vector3.ZERO,"elev_min":0.0,"elev_max":100.0,
		"grader":null,"road_grader":grader,"collision":true}
	var started := Time.get_ticks_msec()
	var terrain := Mesher.compute(request)
	var elapsed := Time.get_ticks_msec()-started
	var vertices: PackedVector3Array = terrain.arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = terrain.arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	var flat_vertices := 0
	for p in vertices:
		assert(p.is_finite())
		if absf(p.z)<=4.0001 and absf(p.x)<50:
			assert(absf(p.y-(20.0+p.x*.1))<.001)
			flat_vertices += 1
	for i in range(0,indices.size(),3):
		var a := Vector2(vertices[indices[i]].x,vertices[indices[i]].z)
		var b := Vector2(vertices[indices[i+1]].x,vertices[indices[i+1]].z)
		var c := Vector2(vertices[indices[i+2]].x,vertices[indices[i+2]].z)
		area += absf((b-a).cross(c-a))*.5
	assert(absf(area-128.0*128.0)<.05 and flat_vertices>0)
	var interior_probes := 0
	for x in [-50.0,-25.0,0.0,25.0,50.0]:
		for z in [-3.0,0.0,3.0]:
			var p := Vector2(x,z)
			var matched := false
			for i in range(0,indices.size(),3):
				var a := vertices[indices[i]]
				var b := vertices[indices[i+1]]
				var c := vertices[indices[i+2]]
				var ab := Vector2(b.x-a.x,b.z-a.z)
				var ac := Vector2(c.x-a.x,c.z-a.z)
				var ap := p-Vector2(a.x,a.z)
				var denominator := ab.cross(ac)
				if absf(denominator)<.00001:
					continue
				var u := ap.cross(ac)/denominator
				var v := ab.cross(ap)/denominator
				if u<-.0001 or v<-.0001 or u+v>1.0001:
					continue
				var height := a.y+u*(b.y-a.y)+v*(c.y-a.y)
				if absf(height-(20.0+x*.1))>=.001:
					print("ROAD_INTERIOR_MISMATCH ",p," ",height," ",[a,b,c])
					quit(1)
					return
				assert(absf(height-(20.0+x*.1))<.001)
				matched = true
			assert(matched)
			interior_probes += 1
	report.earthwork = {"cross_height_before_m":before_delta,"cross_height_after_m":after_delta,"preserved_projected_area_m2":area,
		"vertices":vertices.size(),"triangles":indices.size()/3,"build_ms":elapsed,"flat_core_vertices":flat_vertices,"interior_probes":interior_probes,"collision_grid":terrain.heights.size()}
	var roads: Array = []
	for pair in [["service",3.0],["residential",7.0],["primary",14.0]]:
		roads.append({"type":pair[0],"width":pair[1],"points":[[-60,0,0],[60,0,0]],"structure_tags_verified":true})
	var water := func(_x,_z): return 0.0
	var result := Batch.compute(roads,ground,water,Vector2(32,32),Vector2(-64,-64),true)
	var host := Host.new()
	root.add_child(host)
	var container := Batch.attach(host,result)
	var tiers: Dictionary = {}
	for mesh in container.get_children():
		tiers[mesh.get_meta("road_visibility_tier")] = mesh.visibility_range_end
		assert(mesh.visibility_range_end_margin==200.0)
		for uv in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]:
			assert(uv.x==1.0)
	assert(tiers.small==1600.0 and tiers.medium==3500.0 and tiers.major==9500.0)
	# 경계에서 잘라도 원래 커브의 마이터와 정점은 유지한다.
	var curve := {"type":"residential","width":7.0,"points":[[240,20,0],[260,20,10],[280,20,0]],"structure_tags_verified":true}
	var flat := func(_x,_z,_f): return 20.0
	var grouped := Batch.compute([curve],flat,water,Vector2.ZERO,Vector2.ZERO,true)
	var points := RoadMesh.subdivide_polyline(curve.points)
	var heights: Array[float] = []
	heights.resize(points.size())
	heights.fill(20.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	RoadMesh.build_surface_road(st,points,heights,7.0,flat,Vector2.ZERO,Vector2.ZERO,.85,true)
	assert(_vertices(grouped.paved)==_vertices([st.commit_to_arrays()]))
	report.visibility = {"ranges_m":tiers,"hysteresis_m":200,"cell_m":256,"curve_boundary_vertices_preserved":true}
	# 기준 자료 변경 시 형상 보정을 적용하지 않는다.
	var bad := Grader.new()
	bad.configure("res://fixture/missing.json")
	assert(not bad.enabled)
	report.missing_source_safe = true
	report.full_world_run = false
	var file := FileAccess.open("res://verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ROAD_FORMATION_CHECK_OK ",JSON.stringify(report))
	quit()
