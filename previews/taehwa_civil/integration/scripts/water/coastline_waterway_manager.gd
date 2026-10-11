extends Node3D
class_name CoastlineWaterwayManager

## 벡터 해안선 및 하천/하구 지형 정밀 렌더러
## OSM 실측 벡터 데이터를 활용하여 해안선 완충대와 하천 수로 리본을 생성하고,
## 해양 수면과 하천이 만나는 기수역(Estuary)의 단차와 텍스처 불연속성을 해소합니다.

@export var coastlines_waterways_path: String = ""

var shoreline_material: StandardMaterial3D
var river_water_material: StandardMaterial3D

func _ready() -> void:
	_init_from_map_selection()
	_init_materials()
	load_and_render_vectors()

func _init_from_map_selection() -> void:
	var current_map_id: String = ""
	var root = get_tree().root
	if root.has_node("MapSelectionService"):
		var svc = root.get_node("MapSelectionService")
		if svc and svc.selected_map:
			current_map_id = svc.selected_map.id

	# 울산 맵, 광역 대형 맵 등은 지형 셰이더 및 높이맵 기반 일체형 수면으로 렌더링하므로 별도 3D 리본 로드 차단
	if current_map_id.begins_with("ulsan_") or current_map_id.begins_with("southeast_"):
		coastlines_waterways_path = ""
		return

	if not current_map_id.is_empty():
		var candidate := "res://assets/maps/%s/coastlines_and_waterways.json" % [current_map_id]
		if FileAccess.file_exists(candidate):
			coastlines_waterways_path = candidate

	if coastlines_waterways_path.is_empty() or not FileAccess.file_exists(coastlines_waterways_path):
		# 오직 칸몬 해협 맵일 때만 칸몬 해협 전용 수로 데이터를 폴백으로 로드
		if current_map_id == "kanmon_straits":
			var fallback := "res://assets/maps/kanmon_straits/coastlines_and_waterways.json"
			if FileAccess.file_exists(fallback):
				coastlines_waterways_path = fallback
		else:
			coastlines_waterways_path = ""

func _init_materials() -> void:
	# 1. 해안선 완충대 (백사장/방파제 접점 자연스러운 쇄파대 리본)
	shoreline_material = StandardMaterial3D.new()
	shoreline_material.albedo_color = Color(0.85, 0.88, 0.82, 0.65)
	shoreline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shoreline_material.roughness = 0.35
	shoreline_material.metallic_specular = 0.5
	shoreline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shoreline_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	# 2. 하천/수로 리본 수면 (청록색 흐르는 물결 톤)
	river_water_material = StandardMaterial3D.new()
	river_water_material.albedo_color = Color(0.10, 0.25, 0.35, 0.85)
	river_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	river_water_material.roughness = 0.12
	river_water_material.metallic_specular = 0.8
	river_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	river_water_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

func load_and_render_vectors() -> void:
	if coastlines_waterways_path.is_empty() or not FileAccess.file_exists(coastlines_waterways_path):
		return

	var file := FileAccess.open(coastlines_waterways_path, FileAccess.READ)
	if not file:
		return

	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return

	var coastlines: Array = data.get("coastlines", [])
	var waterways: Array = data.get("waterways", [])

	# 사용자 지침 준수: 해안선에 별도 오브젝트(리본 메쉬)를 생성하지 않고 지형 높이맵 조작으로 표현함
	# _render_coastlines_batched(coastlines)
	_render_waterways_batched(waterways)
	print("[CoastlineWaterwayManager] Disabled coastline ribbon objects (rendered directly on terrain). Rendered %d river channels." % [waterways.size()])

func _render_coastlines_batched(coastlines: Array) -> void:
	if coastlines.is_empty():
		return

	var container := Node3D.new()
	container.name = "CoastlineRibbons"
	add_child(container)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var count: int = 0
	for item in coastlines:
		var pts: Array = item.get("points", [])
		if pts.size() < 2:
			continue

		# 해안선 쇄파대 리본 너비: 8m (해수면과 지형의 단차를 덮는 완충 메쉬)
		_build_vector_ribbon(st, pts, 8.0, 0.15)
		count += 1

		if count >= 1000:
			var m = st.commit()
			var mi = MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = shoreline_material
			container.add_child(mi)
			st.clear()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			count = 0

	if count > 0:
		var m = st.commit()
		var mi = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = shoreline_material
		container.add_child(mi)

func _render_waterways_batched(waterways: Array) -> void:
	if waterways.is_empty():
		return

	var container := Node3D.new()
	container.name = "WaterwayRibbons"
	add_child(container)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var count: int = 0
	for item in waterways:
		var pts: Array = item.get("points", [])
		if pts.size() < 2:
			continue

		var w: float = float(item.get("width", 10.0))
		# 하천 수로 리본: 지형보다 0.2m 위에 부드럽게 얹음
		_build_vector_ribbon(st, pts, w, 0.20)
		count += 1

		if count >= 1000:
			var m = st.commit()
			var mi = MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = river_water_material
			container.add_child(mi)
			st.clear()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			count = 0

	if count > 0:
		var m = st.commit()
		var mi = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = river_water_material
		container.add_child(mi)

func _build_vector_ribbon(st: SurfaceTool, pts: Array, width: float, y_offset: float) -> void:
	var half_w: float = width * 0.5
	var n_pts: int = pts.size()

	for i in range(n_pts - 1):
		var p0_arr: Array = pts[i]
		var p1_arr: Array = pts[i + 1]

		# 기수역(Y <= 0.2m)에서는 바다 수면(Y=0.0)과 매끄럽게 일치하도록 Y 클램핑 및 보정
		var y0: float = float(p0_arr[1]) + y_offset
		var y1: float = float(p1_arr[1]) + y_offset
		if y0 < 0.05:
			y0 = 0.05
		if y1 < 0.05:
			y1 = 0.05

		var p0 := Vector3(float(p0_arr[0]), y0, float(p0_arr[2]))
		var p1 := Vector3(float(p1_arr[0]), y1, float(p1_arr[2]))

		var dir := (p1 - p0).normalized()
		if dir.length_squared() < 0.001:
			continue

		var side := dir.cross(Vector3.UP).normalized() * half_w

		var a := p0 - side
		var b := p0 + side
		var c := p1 + side
		var d := p1 - side

		_add_quad(st, a, b, c, d, Vector3.UP)

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)

	st.set_normal(normal)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)

	st.set_normal(normal)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)

	st.set_normal(normal)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)

	st.set_normal(normal)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)

	st.set_normal(normal)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(d)
