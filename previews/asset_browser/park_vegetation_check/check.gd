extends SceneTree
## 독립 복사본의 실제 Godot 임포트·배치 구조를 검사한다.
const BASE := "res://assets/generated/park_vegetation/"
const Factory = preload("res://assets/generated/park_vegetation/batch_factory.gd")


func _initialize() -> void:
    call_deferred("run")


func run() -> void:
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "catalog.json"))
    var factory := Factory.new()
    var count := 0
    for model in catalog.models:
        for stage in model.lods:
            var mesh: Mesh = factory.mesh_for(stage.path)
            assert(mesh != null and mesh.get_surface_count() == 1)
            var arrays: Array = mesh.surface_get_arrays(0)
            assert(arrays[Mesh.ARRAY_COLOR].size() == arrays[Mesh.ARRAY_VERTEX].size())
            if model.id == "rock_medium" and int(stage.lod_level) == 0:
                print("ROCK VERTEX COLOR: ", arrays[Mesh.ARRAY_COLOR][0])
            assert(arrays[Mesh.ARRAY_INDEX].size() / 3 == int(stage.triangles))
            assert(mesh.get_aabb().size.y > 0)
            count += 1
    var parent := Node3D.new()
    root.add_child(parent)
    var positions: Array[Transform3D] = []
    for i in range(2048):
        positions.append(Transform3D(Basis.IDENTITY, Vector3((i % 64) * 2, 0, (i / 64) * 2)))
    var batches: Array[MultiMeshInstance3D] = factory.add_batches(parent, "flower_low_round", positions)
    var instances := 0
    for batch in batches:
        instances += batch.multimesh.instance_count
        assert(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
        assert(batch.multimesh.use_custom_data)
        assert(batch.multimesh.use_colors)
        assert(batch.multimesh.get_instance_color(0).is_equal_approx(Color.WHITE))
    assert(instances == 2048 * 3)
    print("PARK CHECK OK: ", count, " models, 2048 positions, ", batches.size(), " batches")
    parent.queue_free()
    var scenes := ["lawn_plaza", "flower_path", "naturalist_bed", "bamboo_edge", "shaded_rest"]
    for key in scenes:
        var scene: Node = (load(BASE + "compositions/" + key + ".tscn") as PackedScene).instantiate()
        root.add_child(scene)
        await process_frame
        assert(scene.get_child_count() > 3)
        scene.queue_free()
        await process_frame
    print("PARK COMPOSITIONS OK: 5")
    quit()
