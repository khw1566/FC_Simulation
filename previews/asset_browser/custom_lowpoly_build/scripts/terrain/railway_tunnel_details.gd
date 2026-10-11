extends RefCounted
## 터널 궤도, 측면 설비 및 갱구 부재를 구성한다.

static func build(g, spec: Dictionary) -> void:
	var length := float(spec.length_m)
	var half_width := float(spec.inner_half_width_m)
	var spacing := float(spec.track_spacing_m)
	var gauge := float(spec.gauge_m)
	var slab := str(spec.track_bed) == "slab"
	var rail_top := float(spec.rail_top_y_m)
	for x in [-spacing * 0.5, spacing * 0.5]:
		g.box(Vector3(x, -0.20, length * 0.5), Vector3(3.4 if slab else 3.8, 0.4, length), "bed" if slab else "ballast")
		var count := maxi(1, int(ceil(length / (1.2 if slab else 0.75))))
		for i in range(count):
			var z := (i + 0.5) * length / count
			g.box(Vector3(x, -0.015, z), Vector3(2.5, 0.09, 0.20), "sleepers")
			if not slab:
				for side in [-1.0, 1.0]:
					var pebble_x: float = x + side * (1.45 + 0.12 * sin(i * 1.7))
					g.box(Vector3(pebble_x, 0.012, z), Vector3(0.14, 0.055, 0.19), "ballast_detail")
		for side in [-1.0, 1.0]:
			var rail_x: float = x + side * gauge * 0.5
			g.box(Vector3(rail_x, rail_top - 0.035, length * 0.5), Vector3(0.075, 0.07, length), "rails")
		var wire_height := float(spec.catenary_height_m)
		g.beam(Vector3(x, wire_height, 0), Vector3(x, wire_height, length), 0.025, 0.025, "wires")
		g.beam(Vector3(x, wire_height + 0.5, 0), Vector3(x, wire_height + 0.5, length), 0.018, 0.018, "wires")
		for i in range(maxi(1, int(ceil(length / 8.0)))):
			var z: float = i * 8.0
			g.beam(Vector3(x, wire_height + 0.5, z), Vector3(x, float(spec.inner_height_m) - 0.8, z), 0.06, 0.06, "metal")
			g.beam(Vector3(x, wire_height, z), Vector3(x, wire_height + 0.5, z), 0.05, 0.05, "metal")
	for side in [-1.0, 1.0]:
		var x: float = side * (half_width - 0.60)
		g.box(Vector3(x, 0.025, length * 0.5), Vector3(0.95, 0.31, length), "walkway")
		g.box(Vector3(x - side * 0.64, -0.20, length * 0.5), Vector3(0.22, 0.10, length), "drain")
		g.box(Vector3(side * (half_width - 0.08), 1.10, length * 0.5), Vector3(0.14, 0.14, length), "metal")
		var lights := maxi(1, int(ceil(length / float(spec.light_spacing_m))))
		for i in range(lights):
			var z := (i + 0.5) * length / lights
			g.box(Vector3(side * (half_width - 0.12), 2.55, z), Vector3(0.20, 0.13, 0.65), "metal")
			g.box(Vector3(side * (half_width - 0.24), 2.55, z), Vector3(0.025, 0.09, 0.50), "light")
		g.box(Vector3(side * (half_width - 0.10), 1.6, length * 0.5), Vector3(0.025, 0.22, 0.45), "marker")
	if str(spec.part) != "body":
		var portal_z := length if str(spec.part) == "exit" else 0.0
		var radius := half_width + float(spec.portal_flare_m)
		for side in [-1.0, 1.0]:
			var x: float = side * (radius + 0.75)
			g.box(Vector3(x, 2.1, portal_z), Vector3(1.25, 5.3, 1.1), "portal")
			var z_offset := 1.4 if str(spec.part) == "entry" else -1.4
			g.box(Vector3(x + side * 1.35, 1.25, portal_z + z_offset), Vector3(1.3, 3.6, 3.8), "portal")
		g.box(Vector3(0, float(spec.inner_height_m) + float(spec.portal_flare_m) * 0.65 + 0.35, portal_z),
			Vector3(2.4, 0.25, 0.45), "portal")
