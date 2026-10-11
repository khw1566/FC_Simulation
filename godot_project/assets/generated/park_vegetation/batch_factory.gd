class_name ParkVegetationBatchFactory
extends RefCounted
## 32m 청크와 개별 인스턴스 거리 범위로 소형 군락을 묶는다.
const BASE := "res://assets/generated/park_vegetation/"
const CELL_SIZE := 32.0
var _meshes: Dictionary = {}
var _materials: Dictionary = {}


func _find_mesh(node: Node) -> Mesh:
    if node is MeshInstance3D:
        return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var result: Mesh = _find_mesh(child)
        if result != null:
            return result
    return null


func mesh_for(path: String) -> Mesh:
    if not _meshes.has(path):
        var packed: PackedScene = load(path) as PackedScene
        if packed == null:
            push_error("공원 모델 누락: " + path)
            return null
        var node: Node = packed.instantiate()
        _meshes[path] = _find_mesh(node)
        node.free()
    return _meshes[path] as Mesh


func add_batches(parent: Node3D, key: String, transforms: Array[Transform3D], wind: float = 0.0) -> Array[MultiMeshInstance3D]:
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "catalog.json"))
    var spec: Dictionary = {}
    for model in catalog.models:
        if model.id == key:
            spec = model
            break
    var result: Array[MultiMeshInstance3D] = []
    if spec.is_empty():
        push_error("알 수 없는 공원 모델: " + key)
        return result
    var chunks: Dictionary = {}
    for transform in transforms:
        var cell := Vector2i(floori(transform.origin.x / CELL_SIZE), floori(transform.origin.z / CELL_SIZE))
        if not chunks.has(cell):
            chunks[cell] = []
        chunks[cell].append(transform)
    var material_key := "static" if spec.kind in ["hedge", "rock"] else str(wind)
    if not _materials.has(material_key):
        var mat := ShaderMaterial.new()
        mat.shader = load(BASE + "surface.gdshader")
        mat.set_shader_parameter("wind_strength", 0.0 if material_key == "static" else wind)
        _materials[material_key] = mat
    for cell in chunks:
        for stage in spec.lods:
            var batch := MultiMesh.new()
            batch.transform_format = MultiMesh.TRANSFORM_3D
            batch.use_custom_data = true
            batch.use_colors = true
            batch.mesh = mesh_for(stage.path)
            batch.instance_count = chunks[cell].size()
            var offset := Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)
            for i in range(batch.instance_count):
                var local: Transform3D = chunks[cell][i]
                local.origin -= offset
                batch.set_instance_transform(i, local)
                batch.set_instance_color(i, Color.WHITE)
                batch.set_instance_custom_data(i, Color(fposmod(float(i) * 0.618, 1.0), 0.0, 0.0, 1.0))
            var instance := MultiMeshInstance3D.new()
            instance.name = key + "_lod" + str(stage.lod_level)
            instance.multimesh = batch
            instance.position = offset
            instance.custom_aabb = batch.get_aabb().grow(0.15)
            instance.material_override = _materials[material_key]
            instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            # MultiMesh 자체의 중심 거리 대신 각 군락의 월드 원점 거리로 소거한다.
            # Godot의 visibility_range는 청크 중심 기준이므로 셰이더로 개별 전환한다.
            var stage_key: String = material_key + "_" + str(stage.visibility_begin_m) + "_" + str(stage.visibility_end_m)
            if not _materials.has(stage_key):
                var shader_mat := (_materials[material_key] as ShaderMaterial).duplicate() as ShaderMaterial
                shader_mat.set_shader_parameter("lod_begin", float(stage.visibility_begin_m))
                shader_mat.set_shader_parameter("lod_end", float(stage.visibility_end_m))
                _materials[stage_key] = shader_mat
            instance.material_override = _materials[stage_key]
            instance.visibility_range_end = float(stage.visibility_end_m) + 46.0
            parent.add_child(instance)
            result.append(instance)
    return result
