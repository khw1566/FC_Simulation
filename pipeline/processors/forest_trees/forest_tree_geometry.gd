extends RefCounted
## 공통 숲 수목: 활엽 낙엽수·소나무형·관목·대나무 각 3형태 × LOD 3단.
## 1표면·정점 색 재질. 정점 색 알파 = 흔들림 가중치(줄기 0, 수관 끝 1).
## LOD0 400삼각형 이하(다층 잎 덩이), LOD1 120 이하, LOD2 24 이하(위에서도 둥근 입체 수관).

## kind: [수종, 높이 m, 폭 m, 시드]
const SPECS := {
	"deciduous_a": ["vase", 12.0, 9.0, 11], "deciduous_b": ["round", 8.0, 7.5, 23], "deciduous_c": ["oval", 14.0, 6.0, 37],
	"pine_a": ["pine", 11.0, 7.0, 41], "pine_b": ["pine", 9.0, 6.5, 53], "pine_c": ["pine", 13.0, 6.0, 67],
	"shrub_a": ["shrub", 1.4, 2.0, 71], "shrub_b": ["shrub", 2.0, 2.6, 83], "shrub_c": ["shrub", 1.1, 1.6, 97],
	"bamboo_a": ["bamboo", 9.0, 3.0, 101], "bamboo_b": ["bamboo", 10.5, 3.6, 113], "bamboo_c": ["bamboo", 7.5, 2.6, 127],
}
const BARK := Color(0.30, 0.22, 0.15, 0.0)
const PINE_BARK := Color(0.42, 0.24, 0.16, 0.0)
const BAMBOO_STEM := Color(0.40, 0.48, 0.20, 0.0)
const LEAF := {
	"vase": Color(0.24, 0.40, 0.17), "round": Color(0.30, 0.45, 0.19), "oval": Color(0.21, 0.37, 0.16),
	"pine": Color(0.13, 0.27, 0.15), "shrub": Color(0.25, 0.39, 0.17), "bamboo": Color(0.42, 0.56, 0.20),
}

static func spec(kind: String) -> Array:
	return SPECS[kind]

static func build(kind: String, lod: int) -> MeshInstance3D:
	var data: Array = SPECS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data[3])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clumps: Array = _clumps(str(data[0]), float(data[1]), float(data[2]), rng)
	var leaf: Color = LEAF[data[0]]
	if lod == 2:
		_far_crown(st, clumps, leaf)
	else:
		_wood(st, str(data[0]), float(data[1]), clumps, lod, rng)
		var keep: Array = clumps if lod == 0 else _merge(clumps, 4)
		for i in range(keep.size()):
			var c: Array = keep[i]
			var shade := leaf.lightened(0.08 * float(i % 3) - 0.04 + (0.06 if c[0].y > float(data[1]) * 0.75 else 0.0))
			blob(st, c[0], c[1], 6 if lod == 0 else 5, 4 if lod == 0 else 3, shade, int(data[3]) * 31 + i, c[2])
	var node := MeshInstance3D.new()
	node.name = kind
	node.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	node.mesh.surface_set_material(0, material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## 잎 덩이 목록: [중심, 반경 Vector3, 흔들림 가중치]
static func _clumps(shape: String, height: float, width: float, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	var r := width * 0.5
	match shape:
		"vase":
			for i in range(8):
				var a := TAU * i / 8.0 + rng.randf_range(-0.2, 0.2)
				var y := height * rng.randf_range(0.62, 0.84)
				result.append([Vector3(cos(a) * r * 0.62, y, sin(a) * r * 0.62), Vector3(r * 0.42, height * 0.15, r * 0.42) * rng.randf_range(0.85, 1.1), 0.9])
			result.append([Vector3(0, height * 0.86, 0), Vector3(r * 0.5, height * 0.13, r * 0.5), 1.0])
		"round":
			for i in range(7):
				var a := TAU * i / 7.0 + rng.randf_range(-0.25, 0.25)
				result.append([Vector3(cos(a) * r * 0.55, height * rng.randf_range(0.55, 0.72), sin(a) * r * 0.55), Vector3(r * 0.45, height * 0.2, r * 0.45) * rng.randf_range(0.85, 1.1), 0.85])
			result.append([Vector3(0, height * 0.8, 0), Vector3(r * 0.55, height * 0.18, r * 0.55), 1.0])
		"oval":
			for level in range(4):
				for i in range(2):
					var a := TAU * (i + level * 0.5) / 2.0 + rng.randf_range(-0.3, 0.3)
					var spread := r * (0.42 - level * 0.07)
					result.append([Vector3(cos(a) * spread, height * (0.38 + level * 0.15), sin(a) * spread), Vector3(r * (0.55 - level * 0.08), height * 0.12, r * (0.55 - level * 0.08)), 0.6 + level * 0.12])
		"pine":
			var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			for i in range(6):
				var t := float(i) / 5.0
				var a := rng.randf_range(0.0, TAU)
				var offset := Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.2, 0.55) * (1.0 - t * 0.5)
				result.append([Vector3(0, height * (0.5 + t * 0.42), 0) + lean * t + offset, Vector3(r * (0.55 - t * 0.2), height * 0.07, r * (0.5 - t * 0.2)), 0.5 + t * 0.5])
		"shrub":
			for i in range(5):
				var a := TAU * i / 5.0 + rng.randf_range(-0.3, 0.3)
				var radial := r * (0.45 if i < 4 else 0.0)
				result.append([Vector3(cos(a) * radial, height * (0.38 if i < 4 else 0.62), sin(a) * radial), Vector3(r * 0.5, height * 0.42, r * 0.5) * rng.randf_range(0.85, 1.1), 0.7])
		"bamboo":
			var stalks := 6 if width > 3.2 else 5
			for i in range(stalks):
				var a := TAU * i / float(stalks) + rng.randf_range(-0.4, 0.4)
				var base := Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.15, 0.45)
				var h := height * rng.randf_range(0.82, 1.0)
				var top := base * 2.2 + Vector3(0, h, 0)
				# 대나무 잎은 줄기 위쪽 1/3을 감싸는 길쭉한 덩이로, 이웃 줄기와 겹쳐 하나의 군집처럼 보이게 한다.
				result.append([top + Vector3(0, -h * 0.26, 0), Vector3(0.85, h * 0.3, 0.85), 1.0, base])
	return result

## 줄기·가지. 대나무는 덩이마다 줄기 하나.
static func _wood(st: SurfaceTool, shape: String, height: float, clumps: Array, lod: int, rng: RandomNumberGenerator) -> void:
	var segments := 6 if lod == 0 else 4
	if shape == "shrub":
		return
	if shape == "bamboo":
		for c in clumps:
			var base: Vector3 = c[3]
			var top: Vector3 = c[0]
			_limb(st, base, top, 0.06, 0.035, 4 if lod == 0 else 3, BAMBOO_STEM)
		return
	var bark := PINE_BARK if shape == "pine" else BARK
	var trunk_top := Vector3(0, height * (0.55 if shape != "oval" else 0.75), 0)
	if shape == "pine":
		trunk_top = (clumps[clumps.size() - 1][0] as Vector3) * Vector3(1, 0.92, 1)
		var bend := Vector3(rng.randf_range(-0.5, 0.5), height * 0.45, rng.randf_range(-0.5, 0.5))
		_limb(st, Vector3.ZERO, bend, height * 0.035, height * 0.027, segments, bark)
		_limb(st, bend, trunk_top, height * 0.027, height * 0.012, segments, bark)
	else:
		_limb(st, Vector3.ZERO, trunk_top, height * 0.035, height * 0.022, segments, bark)
	if lod == 0:
		var count := mini(4, clumps.size())
		for i in range(count):
			var target: Vector3 = clumps[i * clumps.size() / count][0]
			_limb(st, trunk_top * 0.85, target * Vector3(0.8, 0.95, 0.8), height * 0.012, height * 0.006, 4, bark)

## 원통형 가지(양 끝 반경). 기존 cone은 수직 전용이라 임의 방향 원뿔대를 만든다.
static func _limb(st: SurfaceTool, from: Vector3, to: Vector3, r0: float, r1: float, segments: int, color: Color) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var other := axis.cross(side)
	var center := (from + to) * 0.5
	for i in range(segments):
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		var da := side * cos(a) + other * sin(a)
		var db := side * cos(b) + other * sin(b)
		solid_triangle(st, from + da * r0, to + da * r1, to + db * r1, color, center)
		solid_triangle(st, from + da * r0, to + db * r1, from + db * r0, color, center)

## 울퉁불퉁한 잎 덩이(공유 정점마다 결정적 반경 잡음). 알파 = 흔들림 가중치.
static func blob(st: SurfaceTool, center: Vector3, radii: Vector3, segments: int, rings: int, color: Color, seed_value: int, sway: float) -> void:
	var tint := Color(color.r, color.g, color.b, sway)
	for ring in range(rings):
		for i in range(segments):
			var p: Array[Vector3] = []
			for uv in [Vector2i(i, ring), Vector2i(i + 1, ring), Vector2i(i + 1, ring + 1), Vector2i(i, ring + 1)]:
				var angle := TAU * float(uv.x % segments) / segments
				var latitude := PI * float(uv.y) / rings
				var noise := 1.0 + 0.16 * _hash(seed_value, uv.x % segments, uv.y) if uv.y > 0 and uv.y < rings else 1.0
				p.append(center + Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle)) * radii * noise)
			var shade := tint.darkened(0.18 * float(ring) / rings)
			shade.a = sway
			solid_triangle(st, p[0], p[1], p[2], shade, center)
			solid_triangle(st, p[0], p[2], p[3], shade, center)

## LOD2: 덩이 전체를 감싸는 단일 입체 수관(6×3 = 24삼각형).
static func _far_crown(st: SurfaceTool, clumps: Array, leaf: Color) -> void:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for c in clumps:
		var center: Vector3 = c[0]
		var radii: Vector3 = c[1]
		low = low.min(center - radii)
		high = high.max(center + radii)
	var bottom := maxf(0.0, low.y)
	var mid := Vector3((low.x + high.x) * 0.5, (bottom + high.y) * 0.5, (low.z + high.z) * 0.5)
	var radii := Vector3((high.x - low.x) * 0.5, (high.y - bottom) * 0.5, (high.z - low.z) * 0.5)
	blob(st, mid, radii, 6, 3, leaf.lightened(0.06), 7, 0.4)

## LOD1용: 가까운 덩이끼리 묶어 count개로 줄인다(높이 순 정렬 후 균등 분할).
static func _merge(clumps: Array, count: int) -> Array:
	var sorted := clumps.duplicate()
	sorted.sort_custom(func(a, b): return (a[0] as Vector3).y < (b[0] as Vector3).y)
	var result: Array = []
	var size := maxi(1, int(ceil(float(sorted.size()) / count)))
	for start in range(0, sorted.size(), size):
		var center := Vector3.ZERO
		var radii := Vector3.ZERO
		var sway := 0.0
		var group := sorted.slice(start, mini(start + size, sorted.size()))
		for c in group:
			center += c[0]
			radii = radii.max(c[1])
			sway += float(c[2])
		center /= group.size()
		var spread := 0.0
		for c in group:
			spread = maxf(spread, Vector2((c[0] as Vector3).x - center.x, (c[0] as Vector3).z - center.z).length())
		result.append([center, radii + Vector3(spread * 0.8, 0.0, spread * 0.8), sway / group.size()])
	return result

static func _hash(seed_value: int, x: int, y: int) -> float:
	var n := (seed_value * 73856093) ^ (x * 19349663) ^ (y * 83492791)
	n = (n ^ (n >> 13)) * 1274126177 & 0x7fffffff
	return float(n % 2000) / 1000.0 - 1.0

## 닫힌 입체의 면. Godot 앞면(시계 방향)이 바깥(inside 반대쪽)을 향하도록 감기 순서를 맞추고 법선은 바깥으로 둔다.
static func solid_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 0.00000001:
		return
	if cross.dot((a + b + c) / 3.0 - inside) > 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	st.set_color(color)
	st.set_normal(-cross.normalized())
	for p in [a, b, c]:
		st.add_vertex(p)
