extends SceneTree
## 임포터 대신 GLTFDocument로 읽고 검증용 SCN을 프리뷰 작업 공간에만 저장한다.
const URI = "res://assets/generated/harbor_assets/"

func _initialize() -> void:
	var glbs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://glbs.json"))
	for relative in glbs:
		var path: String = "res://" + str(relative)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(path, state) == OK, "GLB 읽기 실패")
		var node := document.generate_scene(state)
		assert(node != null)
		owners(node, node)
		var packed := PackedScene.new()
		assert(packed.pack(node) == OK)
		assert(ResourceSaver.save(packed, path.replace(".glb", ".scn")) == OK)
		node.free()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	var markers := 0
	var colliders := 0
	for key in catalog.models:
		var metadata: Dictionary = catalog.models[key]
		var node := (load(URI + str(key) + ".tscn") as PackedScene).instantiate()
		assert(triangles(node) == int(metadata.triangles), "메시 삼각형 수 변경")
		for port in metadata.ports:
			var marker := node.get_node(str(port.name)) as Marker3D
			assert(marker != null)
			assert(marker.position.distance_to(vector(port.position_m)) < 0.00001)
			assert((-marker.basis.z).distance_to(vector(port.outward_direction)) < 0.00001)
			assert(str(marker.get_meta("profile")) == str(port.profile))
			markers += 1
		for index in metadata.collision_shapes.size():
			var shape := node.get_node("Collision/Shape" + str(index)) as CollisionShape3D
			assert(shape != null and shape.shape != null)
			colliders += 1
		if str(metadata.category) == "lighthouse":
			assert(not node.get_node("NavigationLight").visible)
		node.free()
	for key in catalog.assemblies:
		var node := (load(URI + str(key) + ".tscn") as PackedScene).instantiate()
		assert(node.get_child_count() == catalog.assemblies[key].placements.size() + catalog.assemblies[key].get("external_instances", []).size())
		node.free()
	print("HARBOR CHECK OK: models=", catalog.models.size(), " assemblies=", catalog.assemblies.size(), " GLBs=", glbs.size(), " markers=", markers, " colliders=", colliders)
	var file := FileAccess.open("res://verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"models":catalog.models.size(),"assemblies":catalog.assemblies.size(),"glbs":glbs.size(),"markers":markers,"colliders":colliders}, "  "))
	quit()

func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func owners(node: Node, parent: Node) -> void:
	for child in node.get_children():
		child.owner = parent
		owners(child, parent)

func triangles(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		count += node.mesh.get_faces().size() / 3
	for child in node.get_children():
		count += triangles(child)
	return count
