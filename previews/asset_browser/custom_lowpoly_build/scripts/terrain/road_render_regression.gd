extends SceneTree

const Roads = preload("res://scripts/terrain/road_mesh_builder.gd")
const Classifier = preload("res://scripts/terrain/road_segment_classifier.gd")
const Terrain = preload("res://scripts/terrain/terrain_chunk_manager.gd")
const Chunk = preload("res://scripts/terrain/terrain_chunk.gd")
const Tessellator = preload("res://scripts/terrain/road_terrain_tessellator.gd")
const RoadManager = preload("res://scripts/terrain/building_road_manager.gd")
var _results: Dictionary = {}
var _failed: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _expect(label: String, passed: bool) -> void:
	_results[label] = passed
	_failed = _failed or not passed

func _run() -> void:
	var points: Array[Vector3] = []
	for i in range(11):
		points.append(Vector3(i * 10, 0, 0))
	var weak_water: Array[float] = []
	weak_water.resize(11)
	weak_water.fill(0.2)
	_expect("저지대_약한수계_교량오판정없음", not Classifier.classify({}, points, weak_water).has(1))
	_expect("터널태그_수계보다우선", Classifier.classify({"tunnel": true, "bridge": true}, points, weak_water).count(2) == 10)
	_expect("문자열_no_교량아님", not Classifier.tag_enabled({"bridge": "no"}, "bridge"))
	_expect("이전스키마_is_bridge_인식", Classifier.tag_enabled({"is_bridge": true}, "bridge"))
	var river: Array[float] = [0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0]
	_expect("양안이있는연속하천_교량감지", Classifier.classify({}, points, river).count(1) == 5)
	var a := {"points": [[0, 4, 0], [30, 4, 0]], "bridge": true}
	var b := {"points": [[30, 4, 0], [0, 4, 0]], "bridge": true}
	_expect("역방향_완전중복감지", Classifier.geometry_key(a) == Classifier.geometry_key(b))
	b["layer"] = 1
	_expect("다른층_도로보존", Classifier.geometry_key(a) != Classifier.geometry_key(b))
	_expect("연속중복정점제거", Roads.subdivide_polyline([[0, 0, 0], [0, 0, 0], [5, 0, 0]]).size() == 2)
	var short_bridge := SurfaceTool.new()
	short_bridge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bridge_points: Array[Vector3] = [Vector3(0, 10, 0), Vector3(20, 10, 0)]
	var bottom: Array[float] = [0.0, 0.0]
	Roads.build_universal_bridge(short_bridge, bridge_points, bottom, 12)
	_expect("짧은교량_시작교각중복없음", short_bridge.commit().get_faces().size() / 3 == 14)
	var clipped := SurfaceTool.new()
	clipped.begin(Mesh.PRIMITIVE_TRIANGLES)
	Tessellator.add_quad(clipped, [Vector3(-13, 4, -7), Vector3(-13, 4, 7), Vector3(12, 4, 7), Vector3(12, 4, -7)], Vector2(8, 8), Vector2.ZERO)
	var faces := clipped.commit().get_faces()
	var area: float = 0
	for i in range(0, faces.size(), 3):
		area += (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length() / 2
	_expect("지형경계분할_면적보존", absf(area - 350.0) < 0.01)
	var road_manager := RoadManager.new()
	road_manager.buildings_roads_path = "res://assets/maps/kanmon_straits/buildings_and_roads.json"
	var road_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(road_manager.buildings_roads_path))
	var actual_roads: Array = road_data.roads
	road_manager._apply_road_metadata(actual_roads)
	var restored: int = 0
	for road_data_item in actual_roads:
		if road_data_item.has("osm_id"):
			restored += 1
	_expect("실제도로_속성연결", restored == actual_roads.size())
	var changed_geometry := {"id": actual_roads[0].id, "points": [[0, 0, 0], [1, 0, 0]], "width": 99.0}
	road_manager._apply_road_metadata([changed_geometry])
	_expect("좌표다른_옛속성적용방지", is_equal_approx(changed_geometry.width, 99.0))
	road_manager.free()
	var world := Node3D.new()
	root.add_child(world)
	var image := Image.create(256, 256, false, Image.FORMAT_RF)
	for y in range(256):
		for x in range(256):
			var height: float = 0.25 + 0.11 * sin(x * 0.18) * cos(y * 0.11) + 0.08 * sin(x * 0.045)
			image.set_pixel(x, y, Color(height, 0, 0))
	var terrain := Terrain.new()
	terrain._full_heightmap_image = image
	terrain.terrain_world_size = 1024
	terrain.min_elevation = 0
	terrain.max_elevation = 200
	terrain.grid_chunks_x = 1
	terrain.grid_chunks_y = 1
	var terrain_material := StandardMaterial3D.new()
	terrain_material.albedo_color = Color(0.52, 0.56, 0.49)
	var chunk := Chunk.new()
	chunk.init_chunk(Vector2i.ZERO, 1024, Vector3.ZERO, image, 0, 200)
	world.add_child(chunk)
	terrain.active_chunks[Vector2i.ZERO] = chunk
	var road_material: Material = terrain.create_road_material()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [-110.0, 0.0, 110.0]:
		var path := Roads.subdivide_polyline([[-480, 0, z], [0, 0, z + 75], [480, 0, z - 35]])
		var heights: Array[float] = []
		for p in path:
			heights.append(terrain.get_terrain_elevation(p.x, p.z))
		Roads.build_surface_road(surface, path, heights, 18, func(x: float, zz: float, _fallback: float): return terrain.get_terrain_elevation(x, zz), Vector2(8, 8), Vector2(-512, -512))
	var road := MeshInstance3D.new()
	road.mesh = surface.commit()
	road.material_override = road_material
	# 셰이더 변위 후에도 도로가 컬링되지 않도록 전체 고도 범위를 포함한다.
	road.custom_aabb = AABB(Vector3(-512, -5, -512), Vector3(1024, 210, 1024))
	world.add_child(road)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -20, 0)
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.17, 0.19)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(640, 620, 810)
	camera.near = 2
	camera.far = 4000
	camera.look_at(Vector3(0, 40, 0))
	camera.make_current()
	for lod in [0, 1, 2]:
		chunk.update_lod(lod, terrain_material)
		terrain._sync_road_lods()
		_expect("LOD_%d_동기화" % lod, is_equal_approx(terrain._road_lod_image.get_pixel(0, 0).r, float(lod)))
		for i in range(3):
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../results/road_lod_%d.png" % lod))
	var file := FileAccess.open("res://../results/road_render_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": not _failed, "checks": _results}, "  "))
	file.close()
	print(JSON.stringify(_results))
	terrain.free()
	world.free()
	quit(1 if _failed else 0)

