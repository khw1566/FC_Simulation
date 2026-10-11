extends RefCounted
class_name RoadEarthworkMesher

## 원래 지형 삼각형을 노반 경계에서 절단한다. 균일 고밀도 격자 없이 좁은 수평 단면을 만든다.
const PIECE_LIMIT := 4096
const Detail = preload("res://scripts/terrain/road_earthwork_detail.gd")

static func add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3,
	candidates: Array, road_grader: RefCounted, rail_grader: RefCounted, rail_segments: Array, size: float, dense: bool = false) -> void:
	var lower := Vector2(a.x,a.z).min(Vector2(b.x,b.z)).min(Vector2(c.x,c.z))+Vector2(center.x,center.z)
	var upper := Vector2(a.x,a.z).max(Vector2(b.x,b.z)).max(Vector2(c.x,c.z))+Vector2(center.x,center.z)
	var nearby: Array = []
	for s in candidates:
		if s.lower.x<=upper.x and s.upper.x>=lower.x and s.lower.y<=upper.y and s.upper.y>=lower.y:
			nearby.append(s)
	# 밀집 구간은 작은 국소 문제로 나눠 여러 도로의 절단선 조합이 증가하지 않게 한다.
	var edge := maxf(Vector2(a.x-b.x,a.z-b.z).length(),maxf(Vector2(a.x-c.x,a.z-c.z).length(),Vector2(b.x-c.x,b.z-c.z).length()))
	dense = dense or nearby.size()>12
	if dense and not nearby.is_empty() and Detail.needs_split(a+center,b+center,c+center,road_grader,nearby,edge):
		var ab := (a+b)*.5
		var bc := (b+c)*.5
		var ca := (c+a)*.5
		for triangle in [[a,ab,ca],[ab,b,bc],[ca,bc,c],[ab,bc,ca]]:
			add_triangle(surface,triangle[0],triangle[1],triangle[2],center,nearby,road_grader,rail_grader,rail_segments,size,true)
		return
	candidates = nearby
	var pieces: Array = [[a+center,b+center,c+center]]
	# 밀집 구역은 높이 오차 표본에 따라 2~16m로 세분화하여 교차 절단 조합을 피한다.
	for s in ([] if dense else candidates):
		var from := Vector2(s.a.x,s.a.z)
		var to := Vector2(s.b.x,s.b.z)
		var along := (to-from).normalized()
		var across := Vector2(-along.y,along.x)
		var width: float = s.half
		var outer: float = s.half+s.blend
		var limits := [[from+across*outer,-across], [from-across*outer,across],
			[from-along*outer,along], [to+along*outer,-along]]
		var core := [[from+across*width,across], [from-across*width,across], [from,along], [to,along]]
		var updated: Array = []
		for polygon in pieces:
			var lo := Vector2(INF,INF)
			var hi := Vector2(-INF,-INF)
			for p: Vector3 in polygon:
				lo = lo.min(Vector2(p.x,p.z))
				hi = hi.max(Vector2(p.x,p.z))
			if hi.x < s.lower.x or lo.x > s.upper.x or hi.y < s.lower.y or lo.y > s.upper.y or pieces.size() >= PIECE_LIMIT:
				updated.append(polygon)
				continue
			# 노반 사각형 밖은 더 나누지 않는다. 절단선이 다른 도로까지 뻗는 조합 폭증을 막는다.
			var inside: Array = polygon
			for plane in limits:
				if inside.size()<3:
					break
				var halves := _split(inside,plane[0],plane[1])
				if halves[1].size()>=3:
					updated.append(halves[1])
				inside = halves[0]
			if inside.size()<3:
				continue
			var divided: Array = [inside]
			for plane in core:
				var next: Array = []
				for part in divided:
					for side in _split(part,plane[0],plane[1]):
						if side.size() >= 3:
							next.append(side)
				divided = next
			updated.append_array(divided)
		pieces = updated
	for polygon in pieces:
		for i in range(1,polygon.size()-1):
			var vertices: Array[Vector3] = []
			for original: Vector3 in [polygon[0],polygon[i],polygon[i+1]]:
				var p := original
				p.y = road_grader.corrected_height(p,candidates)
				vertices.append(p-center)
			if (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).length_squared() < .000001:
				continue
			if rail_grader and not rail_segments.is_empty():
				rail_grader.add_triangle(surface,vertices[0],vertices[1],vertices[2],center,rail_segments,size)
			else:
				for p in vertices:
					surface.set_uv(Vector2(p.x,p.z)/size+Vector2(.5,.5))
					surface.add_vertex(p)

static func _split(polygon: Array, origin: Vector2, normal: Vector2) -> Array:
	var positive: Array = []
	var negative: Array = []
	var previous: Vector3 = polygon[-1]
	var pd := (Vector2(previous.x,previous.z)-origin).dot(normal)
	var all_on_plane := true
	for current: Vector3 in polygon:
		var d := (Vector2(current.x,current.z)-origin).dot(normal)
		all_on_plane = all_on_plane and absf(d)<=.00001
		if (d > .00001 and pd < -.00001) or (d < -.00001 and pd > .00001):
			var cut := previous.lerp(current,pd/(pd-d))
			positive.append(cut)
			negative.append(cut)
		if d >= -.00001:
			positive.append(current)
		if d <= .00001:
			negative.append(current)
		previous = current
		pd = d
	# 경계 위의 다각형을 양쪽에 중복 출력하지 않는다.
	if all_on_plane:
		return [polygon, []]
	return [positive,negative]
