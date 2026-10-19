extends SceneTree
## 경량 지형 청크 벤치: 실제 울산 높이맵·노반 자료로 시작 위치 주변 LOD0 청크 메시를 병렬 생성한다.
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")
const Grader = preload("res://scripts/terrain/road_formation_grader.gd")
const WORLD := 80000.0
const CHUNKS := 11
const LOW := -30.0
const HIGH := 1300.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var res := int(args.get("res", "128"))
	var detail := float(args.get("detail", "2"))
	var split := int(args.get("split", "2"))
	var radius := int(args.get("radius", "1"))
	var t0 := Time.get_ticks_msec()
	var image := Image.load_from_file(args.height)
	image.convert(Image.FORMAT_RF)
	var t_img := Time.get_ticks_msec() - t0
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args.formation.path_join("index.json")))
	var grader := Grader.new()
	grader._folder = args.formation
	grader._tiles = index.tiles
	grader.enabled = true
	if grader.has_method("bind_surface"):
		grader.bind_surface(load("res://scripts/terrain/terrain_surface_model.gd").new(image, WORLD, Vector2i(CHUNKS, CHUNKS), res, LOW, HIGH))
	var tile := image.get_width() / CHUNKS
	var size := WORLD / CHUNKS
	var jobs: Array = []
	for cy in range(5 - radius, 6 + radius):
		for cx in range(5 - radius, 6 + radius):
			var px0 := cx * tile
			var py0 := cy * tile
			var rect := Rect2i(px0, py0, mini((cx + 1) * tile + 1, image.get_width()) - px0, mini((cy + 1) * tile + 1, image.get_height()) - py0)
			var center := Vector3((cx + 0.5) * size - WORLD * 0.5, 0, (cy + 0.5) * size - WORLD * 0.5)
			var request := {"image": image.get_region(rect), "grid_res": res, "size": size, "center": center, "elev_min": LOW, "elev_max": HIGH,
				"grader": null, "road_grader": null if args.has("noroad") else grader, "road_detail_edge": detail, "road_terrain_edge": float(args.get("edge", "12")), "collision": true}
			jobs.append({"coord": [cx, cy], "request": request, "result": null, "ms": 0})
	var started := Time.get_ticks_msec()
	var tasks: Array = []
	for job in jobs:
		tasks.append(WorkerThreadPool.add_task(func():
			var s := Time.get_ticks_msec()
			job.result = Mesher.compute(job.request)
			job.ms = Time.get_ticks_msec() - s, false, "bench"))
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	var wall := Time.get_ticks_msec() - started
	var report := {"res": res, "detail": detail, "edge": float(args.get("edge", "12")), "image_ms": t_img, "wall_ms": wall, "threads": OS.get_processor_count(), "chunks": []}
	var total_tris := 0
	for job in jobs:
		var arrays: Array = job.result.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var r: Dictionary = job.request
		var half: float = r.size * 0.5
		# 열린 내부 변(구멍·T자 접합) 수와 원지형 대비 최대 고도 편차
		var edges := {}
		for i in range(0, idx.size(), 3):
			for e in [[idx[i], idx[i + 1]], [idx[i + 1], idx[i + 2]], [idx[i + 2], idx[i]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				edges[key] = int(edges.get(key, 0)) + 1
		var open := 0
		for key in edges:
			if edges[key] == 1:
				var a := verts[key.x]
				var b := verts[key.y]
				var border := (absf(a.x) > half - 0.01 and absf(b.x) > half - 0.01 and is_equal_approx(a.x, b.x)) or (absf(a.z) > half - 0.01 and absf(b.z) > half - 0.01 and is_equal_approx(a.z, b.z))
				if not border:
					open += 1
		var deviations := PackedFloat32Array()
		var img: Image = r.image
		var step: float = r.size / res
		for i in range(0, verts.size(), maxi(1, verts.size() / 20000)):
			var p := verts[i]
			var g := (Vector2(p.x, p.z) + Vector2.ONE * half) / step
			var cell := g.floor().clamp(Vector2.ZERO, Vector2.ONE * (res - 1))
			var f := g - cell
			var w := img.get_width()
			var h := img.get_height()
			var sa := Mesher.sample_bilinear(img, cell.x / res, cell.y / res, w, h)
			var sb := Mesher.sample_bilinear(img, (cell.x + 1) / res, cell.y / res, w, h)
			var sc := Mesher.sample_bilinear(img, cell.x / res, (cell.y + 1) / res, w, h)
			var sd := Mesher.sample_bilinear(img, (cell.x + 1) / res, (cell.y + 1) / res, w, h)
			var v := sa + f.x * (sb - sa) + f.y * (sc - sa) if f.x + f.y <= 1 else sd + (1 - f.x) * (sc - sd) + (1 - f.y) * (sb - sd)
			deviations.append(absf(p.y - (LOW + v * (HIGH - LOW))))
		deviations.sort()
		var n := deviations.size()
		total_tris += idx.size() / 3
		var crack := _cracks(verts, idx, edges, half) if job.coord == [5, 5] else {}
		report.chunks.append({"crack": crack, "coord": job.coord, "ms": job.ms, "triangles": idx.size() / 3, "vertices": verts.size(), "open_interior_edges": open,
			"dev_p99_m": deviations[int(n * 0.99)], "dev_max_m": deviations[n - 1], "dev_over_3m": deviations.size() - deviations.bsearch(3.0)})
	report["triangles"] = total_tris
	var out := FileAccess.open(args.out, FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	print("BENCH_OK ", JSON.stringify({"wall_ms": wall, "triangles": total_tris}))
	quit()

## T자 접합의 실제 수직 틈: 열린 내부 변 위에 놓인 다른 열린 변 정점과 그 변 보간 고도의 차.
func _cracks(verts: PackedVector3Array, idx: PackedInt32Array, edges: Dictionary, half: float) -> Dictionary:
	var open: Array = []
	var hash := {}
	for key in edges:
		if edges[key] != 1:
			continue
		open.append(key)
		for v in [key.x, key.y]:
			var c := Vector2i(floori(verts[v].x / 16.0), floori(verts[v].z / 16.0))
			if not hash.has(c):
				hash[c] = {}
			hash[c][v] = true
	var stride := maxi(1, open.size() / 60000)
	var checked := 0
	var gaps := 0
	var big := 0
	var worst := 0.0
	for e in range(0, open.size(), stride):
		var key: Vector2i = open[e]
		var a := verts[key.x]
		var b := verts[key.y]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		if l2 < 0.0001:
			continue
		checked += 1
		var lo := Vector2i(floori(minf(a.x, b.x) / 16.0), floori(minf(a.z, b.z) / 16.0))
		var hi := Vector2i(floori(maxf(a.x, b.x) / 16.0), floori(maxf(a.z, b.z) / 16.0))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				for v in hash.get(Vector2i(cx, cz), {}):
					if v == key.x or v == key.y:
						continue
					var p := verts[v]
					var ap := Vector2(p.x - a.x, p.z - a.z)
					var t := ap.dot(ab) / l2
					if t <= 0.001 or t >= 0.999 or absf(ap.cross(ab)) / sqrt(l2) > 0.01:
						continue
					var gap := absf(p.y - lerpf(a.y, b.y, t))
					gaps += 1
					worst = maxf(worst, gap)
					if gap > 0.1:
						big += 1
	return {"open_edges": open.size(), "edges_checked": checked, "t_vertices": gaps, "gaps_over_0_1m": big, "max_gap_m": worst}
