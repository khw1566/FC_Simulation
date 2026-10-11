extends RefCounted
## 숲 구역 셀 목록으로 연속 수관 덩어리 메시를 만든다. 셀 모서리마다 인접 셀의 수관 높이 비율을
## 평균해 높이를 정하고, 가장자리 모서리는 이웃 가장자리 모서리 평균으로 옮겨 계단 윤곽을 둥글게 편다.
## 내부는 수관 크기의 굴곡을 준다. 128m 청크로 나누며, 근접 전환은 셰이더가 픽셀 거리로 처리한다.

const CHUNK_M := 128.0
const QUAD := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]

## mass: forest_masses.json의 한 항목. to_target: 원천 월드 xz → 현재 지도 월드 xz(Callable).
## height_at: 현재 지도 월드 (x, z) → 지면 높이(Callable).
static func build(mass: Dictionary, label_size: int, source_size_m: float, to_target: Callable, height_at: Callable) -> Node3D:
	var root := Node3D.new()
	root.name = "ForestMass_%s" % mass.get("zone", "forest")
	var cells := _cells(mass.get("cells", []))
	var emitted: Array[Vector2i] = []
	var coverage := {}
	for cell in cells:
		if float(cells[cell]) <= 0.0 and not _has_canopy_neighbor(cell, cells):
			continue
		emitted.append(cell)
		for offset in QUAD:
			var corner: Vector2i = cell + offset
			if not coverage.has(corner):
				coverage[corner] = _coverage(corner, cells)
	if emitted.is_empty():
		return root
	var material := _material(str(mass.get("texture", "")), float(mass.get("fade_near_m", 100.0)), float(mass.get("fade_band_m", 20.0)))
	var rgb: Array = mass.get("color", [60, 95, 45])
	var base := Color(0.92, 0.92, 0.92) if bool(material.get_shader_parameter("has_texture")) else Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	var canopy := float(mass.get("canopy_height_m", 10.0))
	var variation := float(mass.get("color_variation", 0.12))
	var points := {}
	for corner in coverage:
		points[corner] = _point(corner, coverage, label_size, source_size_m, canopy, to_target, height_at)
	var surfaces := {}
	for cell in emitted:
		var quad: Array[Vector3] = []
		var tint: Array[Color] = []
		for offset in QUAD:
			var corner: Vector2i = cell + offset
			quad.append(points[corner])
			tint.append(_tint(base, variation, corner, float(coverage[corner])))
		var center := (quad[0] + quad[2]) * 0.5
		var key := Vector2i(floori(center.x / CHUNK_M), floori(center.z / CHUNK_M))
		if not surfaces.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[key] = st
		var surface: SurfaceTool = surfaces[key]
		# 높은 쪽 대각선으로 나눠 가장자리 톱니를 줄인다.
		var order := [0, 2, 1, 0, 3, 2] if quad[0].y + quad[2].y >= quad[1].y + quad[3].y else [0, 3, 1, 1, 3, 2]
		for index in order:
			surface.set_color(tint[index])
			surface.set_uv(Vector2(quad[index].x, quad[index].z) / 8.0)
			surface.add_vertex(quad[index])
	for key in surfaces:
		var st: SurfaceTool = surfaces[key]
		st.generate_normals()
		var node := MeshInstance3D.new()
		node.name = "Canopy_%d_%d" % [key.x, key.y]
		node.mesh = st.commit()
		node.material_override = material
		root.add_child(node)
	return root

static func _cells(flat: Array) -> Dictionary:
	var cells := {}
	for i in range(0, flat.size() - 2, 3):
		cells[Vector2i(int(flat[i]), int(flat[i + 1]))] = float(flat[i + 2]) / 255.0
	return cells

static func _coverage(corner: Vector2i, cells: Dictionary) -> float:
	var total := 0.0
	for neighbor in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		total += float(cells.get(corner + neighbor, 0.0)) * 0.25
	return total

## 가장자리(덮임 1 미만) 모서리는 이웃 가장자리 모서리 평균 쪽으로 옮기고, 높이는 3×3 평균 덮임으로 정한다.
static func _point(corner: Vector2i, coverage: Dictionary, label_size: int, source_size_m: float, canopy: float, to_target: Callable, height_at: Callable) -> Vector3:
	var grid := Vector2(corner)
	var smooth := 0.0
	var count := 0
	var edge_sum := Vector2.ZERO
	var edge_count := 0
	var is_edge := float(coverage[corner]) < 0.999
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var other: Vector2i = corner + Vector2i(dx, dy)
			if not coverage.has(other):
				continue
			var value := float(coverage[other])
			smooth += value
			count += 1
			if is_edge and value < 0.999 and absi(dx) + absi(dy) <= 1:
				edge_sum += Vector2(other)
				edge_count += 1
	if is_edge and edge_count > 0:
		grid = grid.lerp(edge_sum / edge_count, 0.7)
	var level := (smooth / count + float(coverage[corner])) * 0.5
	var source := (grid - Vector2(0.5, 0.5)) / float(label_size - 1) - Vector2(0.5, 0.5)
	var xz: Vector2 = to_target.call(source * source_size_m)
	var ground: float = height_at.call(xz.x, xz.y)
	var lump := 0.5 + 0.3 * sin(corner.x * 0.9 + corner.y * 0.35) * sin(corner.y * 0.8 - corner.x * 0.25) + 0.2 * sin(corner.x * 0.11 - corner.y * 0.17)
	var jitter := (_hash(corner) - 0.5) * 0.12
	return Vector3(xz.x, ground + canopy * sqrt(level) * (0.72 + 0.3 * lump + jitter), xz.y)

static func _tint(base: Color, variation: float, corner: Vector2i, coverage: float) -> Color:
	var amount := (_hash(corner + Vector2i(17, 31)) - 0.5) * 2.0 * variation
	var color := base.lightened(amount) if amount > 0.0 else base.darkened(-amount)
	return color.darkened(0.25 * (1.0 - coverage))

static func _hash(p: Vector2i) -> float:
	var n := int(p.x * 374761393 + p.y * 668265263) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177 & 0x7fffffff
	return float(n % 10000) / 10000.0

static func _has_canopy_neighbor(cell: Vector2i, cells: Dictionary) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if float(cells.get(cell + Vector2i(dx, dy), 0.0)) > 0.0:
				return true
	return false

## 거리 디더 전환 셰이더 머티리얼. fade_near_m 안쪽은 그리지 않고 개별 수목에 맡긴다.
static func _material(texture_path: String, fade_near_m: float, fade_band_m: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/forest_mass.gdshader")
	material.set_shader_parameter("fade_near_m", fade_near_m)
	material.set_shader_parameter("fade_band_m", fade_band_m)
	if not texture_path.is_empty() and FileAccess.file_exists(texture_path):
		var image := Image.load_from_file(texture_path)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			material.set_shader_parameter("canopy_texture", ImageTexture.create_from_image(image))
			material.set_shader_parameter("has_texture", true)
	return material
