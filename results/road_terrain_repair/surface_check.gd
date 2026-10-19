extends SceneTree
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")
const Model = preload("res://scripts/terrain/terrain_surface_model.gd")
func _initialize() -> void:
	var image := Image.load_from_file(OS.get_cmdline_user_args()[0])
	image.convert(Image.FORMAT_RF)
	var worst := 0.0
	for r in [64, 128]:
		var res: int = r
		var model := Model.new(image, 80000.0, Vector2i(11, 11), res, -30.0, 1300.0)
		var tile := image.get_width() / 11
		var size := 80000.0 / 11
		for c0 in [Vector2i(5, 5), Vector2i(10, 10), Vector2i(0, 10), Vector2i(10, 3)]:
			var coord: Vector2i = c0
			var px0 := coord.x * tile
			var py0 := coord.y * tile
			var sub := image.get_region(Rect2i(px0, py0, mini((coord.x + 1) * tile + 1, image.get_width()) - px0, mini((coord.y + 1) * tile + 1, image.get_height()) - py0))
			var center := Vector2((coord.x + 0.5) * size - 40000.0, (coord.y + 0.5) * size - 40000.0)
			for k in 4000:
				var local := Vector2(randf(), randf())
				var grid := local * res
				var cell := grid.floor().min(Vector2.ONE * (res - 1))
				var f := grid - cell
				var w := sub.get_width()
				var h := sub.get_height()
				var a := Mesher.sample_bilinear(sub, cell.x / res, cell.y / res, w, h)
				var b := Mesher.sample_bilinear(sub, (cell.x + 1) / res, cell.y / res, w, h)
				var c := Mesher.sample_bilinear(sub, cell.x / res, (cell.y + 1) / res, w, h)
				var d := Mesher.sample_bilinear(sub, (cell.x + 1) / res, (cell.y + 1) / res, w, h)
				var v: float = a + f.x * (b - a) + f.y * (c - a) if f.x + f.y <= 1 else d + (1 - f.x) * (c - d) + (1 - f.y) * (b - d)
				var world := center + (local - Vector2(0.5, 0.5)) * size
				worst = maxf(worst, absf(-30.0 + v * 1330.0 - model.height(world.x, world.y)))
	print("SURFACE_CHECK max_diff_m=", worst)
	quit()
