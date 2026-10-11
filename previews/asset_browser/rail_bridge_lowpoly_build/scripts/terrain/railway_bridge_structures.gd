extends RefCounted
## 박스거더, 강판거더, 트러스, 상로 아치 및 고가교 하부 구조.

static func build(g, spec: Dictionary) -> void:
	var length := float(spec.length_m)
	var width := float(spec.width_m)
	var height := float(spec.pier_height_m)
	var kind := str(spec.kind)
	if kind == "anyang":
		for x in [-3.2, 3.2]:
			g.box(Vector3(x, -0.65, length * 0.5), Vector3(6.1, 0.8, length), "deck")
	else:
		g.box(Vector3(0, -0.65, length * 0.5), Vector3(width, 0.8, length), "deck")
	match kind:
		"box", "viaduct", "station":
			for x in [-width * 0.27, width * 0.27]:
				g.box(Vector3(x, -1.30, length * 0.5), Vector3(width * 0.35, 1.4, length))
			var spans := maxi(1, int(ceil(length / float(spec.get("span_m", 32.0)))))
			for i in range(spans):
				g.pier(i * length / spans, width, height)
			# 접속 규약: 시작 교각은 포함하고 끝 교각은 다음 모듈이 담당한다.
			for i in range(1, spans):
				g.box(Vector3(0, -0.245, i * length / spans), Vector3(width, 0.01, 0.045), "metal")
		"plate":
			for x in [-width * 0.28, width * 0.28]:
				g.box(Vector3(x, -1.3, length * 0.5), Vector3(0.14, 1.7, length), "steel")
				for y in [-2.15, -0.45]:
					g.box(Vector3(x, y, length * 0.5), Vector3(0.70, 0.14, length), "steel")
				for i in range(int(length / 8.0)):
					g.box(Vector3(x, -1.30, (i + 0.5) * 8), Vector3(0.5, 1.55, 0.10), "steel")
			g.pier(0, width, height)
		"truss":
			_truss(g, length, width)
			g.pier(0, width, height)
		"arch":
			arch(g, 0, length, width, float(spec.get("arch_rise_m", 13)), height, false)
			g.pier(0, width, height)
		"anyang":
			var center := float(spec.main_span_m)
			var outer := (length - center) * 0.5
			var offset := 0.0
			for span in [outer, center, outer]:
				arch(g, offset, span, width, float(spec.arch_rise_m), height, true)
				offset += span
			for z in [0.0, outer, outer + center]:
				g.pier(z, width, height)
	if kind == "station":
		for x in [-width * 0.5 - 1.25, width * 0.5 + 1.25]:
			g.box(Vector3(x, 0.40, length * 0.5), Vector3(2.5, 0.8, length), "platform")
			var side: float = -1.0 if x < 0 else 1.0
			g.box(Vector3(x - side * 1.10, 0.805, length * 0.5), Vector3(0.25, 0.01, length), "edge")

static func _truss(g, length: float, width: float) -> void:
	var count := maxi(3, int(ceil(length / 24.0)))
	var panel := length / count
	var top := 8.0
	for x in [-width * 0.49, width * 0.49]:
		g.beam(Vector3(x, -0.4, 0), Vector3(x, -0.4, length), 0.35, 0.45, "steel")
		g.beam(Vector3(x, top, 0), Vector3(x, top, length), 0.35, 0.45, "steel")
		for i in range(count):
			var z0 := i * panel
			var z1 := (i + 1) * panel
			g.beam(Vector3(x, -0.4, z0), Vector3(x, top, z0), 0.30, 0.30, "steel")
			g.beam(Vector3(x, -0.4 if i % 2 == 0 else top, z0),
				Vector3(x, top if i % 2 == 0 else -0.4, z1), 0.28, 0.28, "steel")
		g.beam(Vector3(x, -0.4, length), Vector3(x, top, length), 0.30, 0.30, "steel")
	for i in range(count + 1):
		var z := i * panel
		g.beam(Vector3(-width * 0.49, top, z), Vector3(width * 0.49, top, z), 0.28, 0.28, "steel")
		if i < count:
			g.beam(Vector3(-width * 0.49, top, z), Vector3(width * 0.49, top, z + panel), 0.16, 0.16, "steel")

static func arch(g, begin: float, length: float, width: float, rise: float, height: float, small_arches: bool) -> void:
	var count := 8
	var crown := -2.0
	var ribs: Array[float] = [-width * 0.34, width * 0.34]
	if small_arches:
		# 상하행을 위한 병렬 선체에 각각 두 줄의 주아치 리브를 둔다.
		ribs = [-4.5, -0.9, 0.9, 4.5]
	for x in ribs:
		for i in range(count):
			var t0 := float(i) / count
			var t1 := float(i + 1) / count
			var a := Vector3(x, crown - rise * pow(2 * t0 - 1, 2), begin + length * t0)
			var b := Vector3(x, crown - rise * pow(2 * t1 - 1, 2), begin + length * t1)
			g.beam(a, b, 0.55, 0.80, "arch")
			if i % 3 == 0:
				g.beam(a, Vector3(x, -1.1, a.z), 0.28, 0.32, "arch")
		if small_arches:
			# 주아치 위 소아치는 문헌의 구조적 특징을 단순화한 부재다.
			for section in range(8):
				var z0 := begin + length * section / 8.0
				var z1 := begin + length * (section + 1) / 8.0
				for j in range(2):
					var a_t := float(j) / 2.0
					var b_t := float(j + 1) / 2.0
					var a_low := crown - rise * pow(2 * (section + a_t) / 8.0 - 1, 2)
					var b_low := crown - rise * pow(2 * (section + b_t) / 8.0 - 1, 2)
					var a := Vector3(x, lerpf(a_low, -1.3, sin(PI * a_t)), lerpf(z0, z1, a_t))
					var b := Vector3(x, lerpf(b_low, -1.3, sin(PI * b_t)), lerpf(z0, z1, b_t))
					g.beam(a, b, 0.18, 0.22, "arch")
	for i in range(0, count + 1, 4):
		var t := float(i) / count
		var y := crown - rise * pow(2 * t - 1, 2)
		g.beam(Vector3(ribs[0], y, begin + length * t), Vector3(ribs[-1], y, begin + length * t), 0.25, 0.30, "arch")
	for z in [begin, begin + length]:
		g.box(Vector3(0, -height + 0.7, z), Vector3(width * 0.9, 1.4, 5.0))
