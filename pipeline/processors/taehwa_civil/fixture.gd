extends SceneTree

const Grade = preload("res://scripts/water/river_bed_grade.gd")
const Civil = preload("res://scripts/terrain/taehwa_civil_manager.gd")
const Water = preload("res://scripts/water/taehwa_water_manager.gd")
const Sea = preload("res://scripts/water/kanmon_water_manager.gd")

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var checks: Dictionary = {}
    var terrain := ShaderMaterial.new()
    terrain.shader = load("res://shaders/procedural_terrain.gdshader")
    var image := Image.create(512,512,false,Image.FORMAT_RF)
    image.fill(Color(.27,0,0))
    checks["other_map_excluded"] = not Grade.apply(image,"kanmon_straits",-30,1300,terrain)
    checks["height_range_guard"] = not Grade.apply(image,"ulsan_metro_80km",-10,500,terrain)
    checks["patch_applied"] = Grade.apply(image,"ulsan_metro_80km",-30,1300,terrain)
    checks["outside_preserved"] = absf(image.get_pixel(0,0).r-.27) < .00001
    var count := 0
    for y in image.get_height():
        for x in image.get_width():
            if absf(image.get_pixel(x,y).r-.27) > .00001:
                count += 1
    checks["local_patch_only"] = count > 10 and count < 10000
    var civil := Civil.new()
    root.add_child(civil)
    civil.setup({"id":"ulsan_metro_80km"})
    checks["three_placements"] = civil.placements.size()==3
    civil.setup({"id":"ulsan_metro_80km"})
    checks["placement_idempotent"] = civil.placements.size()==3 and civil.get_child_count()==3
    civil.setup({"id":"kanmon_straits"})
    checks["civil_other_map_excluded"] = civil.placements.is_empty()
    var water := Water.new()
    root.add_child(water)
    await water.setup("ulsan_metro_80km",terrain)
    var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
    checks["all_hydro_chunks"] = water.loaded_chunks==catalog.hydro_chunks.size()
    var colliders := water.find_children("*","CollisionShape3D",true,false)
    checks["bed_collisions"] = colliders.size()==water.loaded_chunks
    checks["transparent_material"] = water.water_material.shader.code.contains("ALPHA =")
    var sea := Sea.new()
    root.add_child(sea)
    sea.set_river_override(terrain.get_shader_parameter("river_overlay_mask"),terrain.get_shader_parameter("river_overlay_rect"))
    var sea_material := sea.get("_water_material") as ShaderMaterial
    checks["sea_overlay_bound"] = sea_material.get_shader_parameter("has_river_overlay")==true
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.position = Vector3(0,12,12)
    camera.look_at(Vector3.ZERO,Vector3.UP)
    camera.current = true
    await physics_frame
    await physics_frame
    var point: Array = catalog.fixture_probe_world_m
    var expected := Vector3(point[0],point[1],point[2])
    var ray := PhysicsRayQueryParameters3D.create(expected+Vector3.UP*20,expected-Vector3.UP*10)
    var hit: Dictionary = water.get_world_3d().direct_space_state.intersect_ray(ray)
    checks["bed_ray_matches_surface"] = not hit.is_empty() and absf(float(hit.position.y)-expected.y)<.5
    for frame in range(4):await process_frame
    var passed := true
    for result in checks.values():
        if result != true: passed = false
    var file := FileAccess.open("res://fixture_results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"passed":passed,"checks":checks,"changed_pixels_512":count,"chunks":water.loaded_chunks},"\t"))
    print("TAEHWA_FIXTURE_", "OK" if passed else "FAILED", " ",checks)
    quit(0 if passed else 1)
