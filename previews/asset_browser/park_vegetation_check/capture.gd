extends SceneTree
const BASE := "res://assets/generated/park_vegetation/"


func _initialize() -> void:
    call_deferred("run")


func run() -> void:
    root.size = Vector2i(1100, 760)
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.16, 0.19, 0.21)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color(0.85, 0.88, 0.90)
    environment.environment.ambient_light_energy = 0.7
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, -35, 0)
    sun.light_energy = 1.4
    world.add_child(sun)
    var camera := Camera3D.new()
    camera.position = Vector3(14, 16, 18)
    camera.fov = 48
    camera.far = 200
    world.add_child(camera)
    camera.look_at(Vector3(0, 0, -0.5))
    camera.current = true
    for key in ["lawn_plaza", "flower_path", "naturalist_bed", "bamboo_edge", "shaded_rest"]:
        var scene: Node = (load(BASE + "compositions/" + key + ".tscn") as PackedScene).instantiate()
        world.add_child(scene)
        for i in range(8):
            await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://" + key + ".png")
        scene.queue_free()
        await process_frame
    print("PARK CAPTURE OK: 5")
    quit()
