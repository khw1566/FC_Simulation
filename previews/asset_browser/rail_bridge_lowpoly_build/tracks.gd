extends SceneTree
## 기존 조립 예제의 열차는 보존하고 철로 부분만 교체한다.
const Track = preload("res://scripts/terrain/railway_track_builder.gd")
const OUTPUT = "res://assets/generated/railway/night_assets"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var services: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/railway/services.json"))
	for profile in services.services:
		for suffix in ["_track", "_night_scene"]:
			var path: String = OUTPUT.path_join(str(profile.id) + suffix + ".scn")
			var original := load(path.replace("res://", "res://originals/")) as PackedScene
			var node := original.instantiate() as Node3D
			var rail := Track.build(PackedVector3Array([Vector3(0, 0, -60), Vector3(0, 0, 460)]), profile, {"bridge": false}, 12000.0)
			if suffix == "_track":
				rail.name = node.name
				for key in node.get_meta_list():
					rail.set_meta(key, node.get_meta(key))
				node.free()
				node = rail
			else:
				var old_track: Node3D = null
				for child in node.get_children():
					if child is Node3D and absf(child.position.z + 60.0) < 0.001:
						old_track = child
				assert(old_track != null, "조립 예제 철로를 찾지 못했습니다")
				rail.name = old_track.name
				var index := old_track.get_index()
				node.remove_child(old_track)
				old_track.free()
				node.add_child(rail)
				node.move_child(rail, index)
			owners(node, node)
			var packed := PackedScene.new()
			assert(packed.pack(node) == OK)
			assert(ResourceSaver.save(packed, path) == OK)
			node.free()
	quit()

func owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		owners(child, owner_node)
