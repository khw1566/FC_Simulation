extends Node3D
class_name TaehwaCivilManager

const BASE := "res://assets/generated/taehwa_civil/"
var placements: Array[Dictionary] = []

func setup(config) -> void:
    for child in get_children():
        child.free()
    placements.clear()
    if config == null or str(config.id) != "ulsan_metro_80km" or not FileAccess.file_exists(BASE+"catalog.json"):
        return
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"catalog.json"))
    for spec in catalog.models:
        if str(spec.placement_status) == "unplaced":
            continue
        var packed := load(str(spec.scene_path)) as PackedScene
        if packed == null:
            continue
        var model := packed.instantiate() as Node3D
        model.name = str(spec.id)
        add_child(model)
        var anchor: Array = spec.anchor_world_m
        model.position = Vector3(anchor[0],anchor[1],anchor[2])
        model.rotation.y = float(spec.axis_yaw_rad)
        placements.append({"model":model,"spec":spec})
    print("[TaehwaCivilManager] 조사 기반 시설 배치: ",placements.size())
