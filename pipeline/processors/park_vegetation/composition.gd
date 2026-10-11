extends Node3D
## 지도 좌표가 없는 소규모 조립 예제.
@export var preset_path: String
const Factory = preload("res://assets/generated/park_vegetation/batch_factory.gd")
var factory := Factory.new()


func _ready() -> void:
    var preset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(preset_path))
    var plane := PlaneMesh.new()
    plane.size = Vector2(20, 20)
    var floor_mesh := MeshInstance3D.new()
    floor_mesh.mesh = plane
    floor_mesh.material_override = load("res://assets/generated/park_vegetation/ground_" + str(preset.ground) + ".tres")
    add_child(floor_mesh)
    var rng := RandomNumberGenerator.new()
    rng.seed = int(preset.seed)
    for index in range(preset.plants.size()):
        var transforms: Array[Transform3D] = []
        var key: String = preset.plants[index]
        var count := 4 if key.begins_with("hedge") or key.begins_with("rock") else 36
        for i in range(count):
            var transform := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)),
                Vector3(-6.0 + index * 3.5 + rng.randf_range(-1.1, 1.1), 0.015, rng.randf_range(-3.0, 6.0)))
            transforms.append(transform)
        factory.add_batches(self, key, transforms, 0.04)
    for item in preset.reused:
        var packed: PackedScene = load(item.path) as PackedScene
        if packed == null:
            continue
        var node := packed.instantiate() as Node3D
        var pos: Array = item.position
        node.position = Vector3(pos[0], pos[1], pos[2])
        add_child(node)
