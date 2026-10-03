extends SceneTree

const FOLDER = "res://assets/maps/kyushu_wide/"

func read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))

func _initialize() -> void:
	build.call_deferred()

func build() -> void:
	var meta := read(FOLDER + "map_meta.json")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2048, 2048)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas: Node2D = load(ProjectSettings.globalize_path("res://") + "../pipeline/processors/kyushu_tactical_canvas.gd").new()
	canvas.meta = meta
	canvas.coastline = read("res://../config/kyushu_coastline_source.geojson")
	canvas.airports = read(meta.assets.airport_placement).airports.filter(func(spec): return preload("res://scripts/terrain/regional_airport_layout.gd").in_map(spec, meta))
	canvas.roads = read(meta.assets.buildings_roads).roads
	canvas.source_meta = read(meta.vector_source_meta)
	var base := Sprite2D.new()
	base.centered = false
	base.texture = ImageTexture.create_from_image(Image.load_from_file(meta.assets.heightmap))
	base.scale = Vector2.ONE * 2048 / base.texture.get_width()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/tactical_terrain_atlas.gdshader")
	material.set_shader_parameter("sea_mask", ImageTexture.create_from_image(Image.load_from_file(meta.assets.sea_mask)))
	material.set_shader_parameter("river_mask", ImageTexture.create_from_image(Image.load_from_file(meta.assets.watermask)))
	material.set_shader_parameter("min_elevation", meta.min_elevation)
	material.set_shader_parameter("max_elevation", meta.max_elevation)
	base.material = material
	viewport.add_child(base)
	viewport.add_child(canvas)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := FOLDER + "kyushu_tactical_map.png"
	if viewport.get_texture().get_image().save_png(path) != OK:
		quit(1)
		return
	meta.assets.tactical_map = path
	meta.preview_image = path
	# 동일 원본 범위의 행정경계를 사용한다.
	meta.assets.districts = canvas.source_meta.assets.districts
	meta.tactical_atlas = {"legend": "북큐슈 구현 범위 28km · 원본 DEM / 수계 / 도로 · 공항 2곳 · 좌클릭: 위치 이동 · 휠: 확대", "airport_count": canvas.airports.size(), "road_count": canvas.roads.size(), "generated_date": "2026-10-03", "terrain_note": "지도와 3D는 같은 원본 지형 범위·고도·해수 마스크를 사용", "source": meta.assets.heightmap}
	write(FOLDER + "map_meta.json", meta)
	var entry := {"file_path": path, "sha256": FileAccess.get_sha256(path), "size_bytes": FileAccess.get_file_as_bytes(path).size(), "bbox": meta.bbox, "elevation": {"min_meters": meta.min_elevation, "max_meters": meta.max_elevation}, "resolution": {"width": 2048, "height": 2048}, "metadata": meta.tactical_atlas}
	for manifest_path in [FOLDER + "manifest.json", "res://assets/generated/manifest.json"]:
		var manifest := read(manifest_path)
		manifest.assets["kyushu_tactical_map"] = entry
		for asset in manifest.assets.values():
			if asset.get("file_path") == FOLDER + "map_meta.json":
				asset.sha256 = FileAccess.get_sha256(FOLDER + "map_meta.json")
				asset.size_bytes = FileAccess.get_file_as_bytes(FOLDER + "map_meta.json").size()
		write(manifest_path, manifest)
	print("큐슈 전용 지도 생성: 공항 ", canvas.airports.size(), "곳 / 도로 ", canvas.roads.size(), "개")
	quit()



