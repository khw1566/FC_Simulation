extends SceneTree
## 실행 시 호출하지 않는 독립 사전 생성 진입점.
const Chunk = preload("res://scripts/terrain/terrain_chunk.gd")
const Sampler = preload("res://scripts/testing/prebaked_rail_sampler.gd")
const Track = preload("res://scripts/terrain/railway_track_builder.gd")
const Formation = preload("res://scripts/terrain/railway_formation_builder.gd")
const Tunnel = preload("res://scripts/terrain/railway_tunnel_geometry.gd")
var report := {"terrain":{},"runtime_geometry_generation":false}

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var started := Time.get_ticks_msec()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://inputs/selection.json"))
	var sampler := Sampler.new()
	root.add_child(sampler)
	sampler.configure(data)
	var origin := Vector3(data.center[0],0,data.center[1])
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.63,0.63,0.63)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for quality in ["light","standard","high"]:
		var chunk := Chunk.new()
		root.add_child(chunk)
		chunk.base_resolution = {"light":32,"standard":64,"high":128}[quality]
		chunk.railway_grader = sampler.grader
		chunk.init_chunk(Vector2i.ZERO,data.world_size,origin,sampler.height,-30.0,1300.0)
		chunk.update_lod_now(0,material)
		var terrain := Node3D.new()
		terrain.name = "BakedTerrain"
		var triangles := 0
		for source: MeshInstance3D in chunk.get_render_meshes():
			var visible_mesh := MeshInstance3D.new()
			visible_mesh.mesh = source.mesh
			visible_mesh.material_override = material
			terrain.add_child(visible_mesh)
			triangles += source.mesh.get_faces().size()/3
		_save(terrain,"terrain_"+quality+".scn")
		report.terrain[quality] = {"triangles":triangles,"grid_resolution":chunk.base_resolution,"rail_edge_m":sampler.grader.edge_limit}
		if quality=="high":
			var physics := Node3D.new()
			physics.name = "BakedCollision"
			var collision_triangles := 0
			for source: MeshInstance3D in chunk.get_render_meshes():
				var body := StaticBody3D.new()
				var shape := CollisionShape3D.new()
				shape.shape = sampler.collision(source.mesh)
				collision_triangles += shape.shape.get_faces().size()/3
				body.add_child(shape)
				physics.add_child(body)
			report["collision_triangles"] = collision_triangles
			_save(physics,"collision.scn")
		chunk.queue_free()
	var infrastructure := Node3D.new()
	infrastructure.name = "BakedRailway"
	for record in data.tracks:
		var points := _points(record.points)
		var node := Track.build(points,data.profiles[record.service],record,10000.0,sampler,true)
		node.position -= origin
		infrastructure.add_child(node)
		var formation := Formation.build(points,sampler,record)
		if formation:
			formation.position = -origin
			infrastructure.add_child(formation)
		# 궤도 상면은 고정 충돌로 저장한다. 침목 등의 장식은 충돌을 만들지 않는다.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(1,points.size()):
			Track._ribbon(st,points[i-1]-origin,points[i]-origin,3.8,0.12,0.0)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = st.commit().create_trimesh_shape()
		body.add_child(shape)
		infrastructure.add_child(body)
	for record in data.tunnels:
		_bake_tunnel(record,infrastructure,origin)
	_monochrome(infrastructure)
	_save(infrastructure,"railway.scn")
	report["track_sections"] = data.tracks.size()
	report["tunnel_sections"] = data.tunnels.size()
	report["bake_ms"] = Time.get_ticks_msec()-started
	var file := FileAccess.open("res://output/bake_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("BAKE_OK ",JSON.stringify(report))
	await process_frame
	await process_frame
	quit()

func _bake_tunnel(record: Dictionary, parent: Node3D, origin: Vector3) -> void:
	var g := Tunnel.new()
	var points := _points(record.points)
	var spec := {"part":"body","inner_half_width_m":7.0,"spring_height_m":3.5,"inner_height_m":10.0,"shell_thickness_m":0.45,"portal_flare_m":0.0,"cross_section_segments":16}
	var ring: PackedVector2Array = g.section(spec,false,0.0)
	for i in range(1,points.size()):
		var a := points[i-1]-origin
		var b := points[i]-origin
		var direction := (b-a).normalized()
		var side := direction.cross(Vector3.UP).normalized()
		var up := side.cross(direction).normalized()
		for j in range(ring.size()):
			var k := (j+1)%ring.size()
			g.quad(a+side*ring[j].x+up*ring[j].y,a+side*ring[k].x+up*ring[k].y,b+side*ring[k].x+up*ring[k].y,b+side*ring[j].x+up*ring[j].y,"lining")
	var node := Node3D.new()
	parent.add_child(node)
	g.finish(node)

func _points(raw: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for p in raw:
		result.append(Vector3(p[0],p[1],p[2]))
	return result

func _monochrome(node: Node) -> void:
	if node is GeometryInstance3D and node.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = node.material_override
		var v := mat.albedo_color.get_luminance()
		mat.albedo_color = Color(v,v,v,mat.albedo_color.a)
	if node is Light3D:
		node.light_color = Color.WHITE
	for child in node.get_children():
		_monochrome(child)

func _owners(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		_owners(child,owner_root)

func _save(node: Node, filename: String) -> void:
	root.add_child(node)
	_owners(node,node)
	var packed := PackedScene.new()
	assert(packed.pack(node)==OK)
	assert(ResourceSaver.save(packed,"res://output/"+filename,ResourceSaver.FLAG_COMPRESS)==OK)
	node.queue_free()
