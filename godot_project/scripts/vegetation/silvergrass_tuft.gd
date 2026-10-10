extends RefCounted
## 억새 필드용 초경량 다발 메시(18삼각형): 꽃대 5, 숙인 이삭 5(각 2삼각형), 잎 3.
## 정점 색 알파 = 높이 비율(흔들림 가중치), UV.x = 1이면 이삭(반짝임 대상). 색은 셰이더가 정한다.

const STALKS := [[Vector2(0.00, 0.00), 1.85, 0.0], [Vector2(0.22, 0.08), 1.55, 1.3], [Vector2(-0.18, 0.16), 1.70, 2.6], [Vector2(-0.12, -0.20), 1.45, 3.9], [Vector2(0.15, -0.17), 1.62, 5.1]]

static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_height := 1.85
	for stalk in STALKS:
		var base := Vector3(stalk[0].x, 0.0, stalk[0].y)
		var height: float = stalk[1]
		var angle: float = stalk[2]
		var lean := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-lean.z, 0.0, lean.x)
		var top := base + lean * 0.12 + Vector3.UP * height
		_tri(st, base - side * 0.015, top, base + side * 0.015, 0.0, height / top_height, 0.0)
		# 이삭: 꽃대 끝에서 바깥으로 숙인 깃털 모양
		var tip := top + lean * 0.26 + Vector3.DOWN * 0.34
		var mid := (top + tip) * 0.5
		_vertex(st, top, height / top_height, 1.0)
		_vertex(st, mid + side * 0.045, height / top_height, 1.0)
		_vertex(st, tip, height / top_height * 0.95, 1.0)
		_vertex(st, top, height / top_height, 1.0)
		_vertex(st, tip, height / top_height * 0.95, 1.0)
		_vertex(st, mid - side * 0.045, height / top_height, 1.0)
	for leaf_angle in [0.8, 2.9, 5.0]:
		var out := Vector3(cos(leaf_angle), 0.0, sin(leaf_angle))
		var side := Vector3(-out.z, 0.0, out.x)
		_tri(st, -side * 0.03, out * 0.45 + Vector3.UP * 0.75, side * 0.03, 0.0, 0.42, 0.0)
	st.generate_normals()
	return st.commit()

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, wa: float, wb: float, plume: float) -> void:
	_vertex(st, a, wa, plume)
	_vertex(st, b, wb, plume)
	_vertex(st, c, wa, plume)

static func _vertex(st: SurfaceTool, p: Vector3, weight: float, plume: float) -> void:
	st.set_color(Color(1.0, 1.0, 1.0, weight))
	st.set_uv(Vector2(plume, 0.0))
	st.add_vertex(p)
