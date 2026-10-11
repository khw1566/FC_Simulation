extends SceneTree

const BASE := "res://assets/generated/taehwa_civil/"

func _initialize() -> void:
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
    for spec in catalog.models:
        var document := GLTFDocument.new()
        var state := GLTFState.new()
        if document.append_from_file(BASE+str(spec.id)+".glb",state) != OK:
            quit(1)
            return
        var model := document.generate_scene(state)
        for child in model.find_children("*","MeshInstance3D",true,false):
            var mesh := child as MeshInstance3D
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            mesh.visibility_range_end = 16000.0
            for i in mesh.mesh.get_surface_count():
                var material := mesh.mesh.surface_get_material(i) as StandardMaterial3D
                var color: Array = catalog.palette[str(material.resource_name)]
                material.albedo_color = Color(color[0],color[1],color[2])
                material.roughness = 0.92
                material.cull_mode = BaseMaterial3D.CULL_DISABLED
            mesh.create_trimesh_collision()
        save_scene(model,BASE+str(spec.id)+".tscn")
    for spec in catalog.hydro_chunks:
        var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://"+str(spec.id)+".json"))
        var node := Node3D.new()
        node.name = str(spec.id)
        node.position = Vector3(data.origin[0],data.origin[1],data.origin[2])
        for is_water in [false,true]:
            if is_water and data.bed_only:
                continue
            var surface := SurfaceTool.new()
            surface.begin(Mesh.PRIMITIVE_TRIANGLES)
            for v in data.vertices:
                surface.set_normal(Vector3.UP)
                surface.set_uv(Vector2(v[3],v[4]))
                var flow := Vector2.ZERO
                if not data.still:
                    # 누적 거리 UV의 기울기와 일치하는 하류 방향.
                    flow = flow_at(float(v[3]),catalog)
                surface.set_uv2(flow*0.5+Vector2(0.5,0.5))
                surface.set_color(Color(float(v[5])/8.0,v[6],v[7],1.0))
                surface.add_vertex(Vector3(float(v[0])-node.position.x,float(v[1])-(0.0 if is_water else float(v[5])),float(v[2])-node.position.z))
            surface.index()
            var mesh := MeshInstance3D.new()
            mesh.name = "Water" if is_water else "Bed"
            mesh.mesh = surface.commit()
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            var material := ShaderMaterial.new()
            material.shader = load("res://shaders/taehwa_flow_water.gdshader" if is_water else "res://shaders/river_gravel.gdshader")
            if is_water:
                material.set_shader_parameter("flow_speed_mps",0.08 if data.still else 0.65)
            mesh.material_override = material
            node.add_child(mesh)
            if not is_water:
                mesh.create_trimesh_collision()
        save_scene(node,str(spec.scene_path))
    for name in ["bancheon","yeocheon"]:
        var terrain_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://"+name+"_terrain.json"))
        var tool := SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        for p in terrain_data.vertices:
            tool.set_normal(Vector3.UP)
            tool.add_vertex(Vector3(p[0],p[1],p[2]))
        tool.index()
        var ground := MeshInstance3D.new()
        ground.name = "TerrainPatch"
        ground.mesh = tool.commit()
        save_scene(ground,"res://"+name+"_terrain.tscn")
    print("TAEHWA_BAKE_OK models=",catalog.models.size()," chunks=",catalog.hydro_chunks.size())
    quit()

func flow_at(chainage: float, catalog: Dictionary) -> Vector2:
    var points: Array = catalog.flow_samples
    var index := clampi(roundi(chainage/float(catalog.flow_step_m)),0,points.size()-1)
    return Vector2(points[index][0],points[index][1])

func save_scene(node: Node, path: String) -> void:
    set_owners(node,node)
    var packed := PackedScene.new()
    if packed.pack(node) != OK or ResourceSaver.save(packed,path) != OK:
        push_error("토목시설·수계 씬 저장 실패: "+path)
        quit(1)
    node.free()

func set_owners(node: Node, owner_node: Node) -> void:
    for child in node.get_children():
        child.owner = owner_node
        set_owners(child,owner_node)
