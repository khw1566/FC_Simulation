extends Node3D
class_name TaehwaWaterManager

const BASE := "res://assets/generated/taehwa_civil/"
var water_material: ShaderMaterial
var loaded_chunks := 0

func setup(map_id: String, terrain_material: ShaderMaterial) -> void:
    for child in get_children():
        child.free()
    loaded_chunks = 0
    if map_id != "ulsan_metro_80km" or terrain_material == null:
        return
    if terrain_material.get_shader_parameter("has_river_overlay") != true:
        return
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE+"catalog.json"))
    water_material = ShaderMaterial.new()
    water_material.shader = load("res://shaders/taehwa_flow_water.gdshader")
    water_material.set_shader_parameter("compatibility_depth",RenderingServer.get_rendering_device()==null)
    water_material.set_shader_parameter("flow_speed_mps",float(catalog.river_policy.flow_speed_mps_visual))
    for spec in catalog.hydro_chunks:
        var scene := load(str(spec.scene_path)) as PackedScene
        if scene == null:
            continue
        var instance := scene.instantiate() as Node3D
        add_child(instance)
        var surface := instance.get_node_or_null("Water") as MeshInstance3D
        if surface != null:
            surface.material_override = water_material
        # 유수지는 유향을 0으로 저장하되 잔물결만 느리게 재생한다.
        if surface != null and str(spec.id).begins_with("basin"):
            var still := water_material.duplicate() as ShaderMaterial
            still.set_shader_parameter("flow_speed_mps",0.08)
            surface.material_override = still
        loaded_chunks += 1
        if loaded_chunks % 8 == 0:
            await get_tree().process_frame
    var mask = terrain_material.get_shader_parameter("river_overlay_mask")
    var rect = terrain_material.get_shader_parameter("river_overlay_rect")
    get_tree().call_group("sea_water_plane","set_river_override",mask,rect)
    print("[TaehwaWaterManager] 투명 수면·하상 구역: ",loaded_chunks)
