extends RefCounted
class_name RailwayTerrainGrader

## 실제 표시 삼각형을 철로 주변에서만 세분화하고 지표를 선로 아래로 낮춘다.
const BUCKET_SIZE := 256.0
var half_width := 12.0
var blend_width := 16.0
var clearance := 0.65
var edge_limit := 10.0
var _buckets: Dictionary = {}

func configure(data: Dictionary) -> void:
	_buckets.clear()
	var settings: Dictionary = data.get("settings",{})
	half_width = float(settings.get("render_formation_half_width_m",12.0))
	blend_width = float(settings.get("render_earthwork_blend_m",16.0))
	clearance = float(settings.get("render_formation_clearance_m",0.65))
	edge_limit = float(settings.get("render_earthwork_edge_m",10.0))
	for track in data.get("tracks",[]):
		if track.bridge or track.tunnel:
			continue
		var points: Array = track.points
		for index in range(1,points.size()):
			var a := Vector3(points[index-1][0],points[index-1][1],points[index-1][2])
			var b := Vector3(points[index][0],points[index][1],points[index][2])
			if Vector2(a.x-b.x,a.z-b.z).length_squared()<0.001:
				continue
			var margin := Vector2.ONE*(half_width+blend_width)
			var lower := Vector2(a.x,a.z).min(Vector2(b.x,b.z))-margin
			var upper := Vector2(a.x,a.z).max(Vector2(b.x,b.z))+margin
			var segment := {"a":a,"b":b,"lower":lower,"upper":upper}
			for y in range(floori(lower.y/BUCKET_SIZE),floori(upper.y/BUCKET_SIZE)+1):
				for x in range(floori(lower.x/BUCKET_SIZE),floori(upper.x/BUCKET_SIZE)+1):
					var key := Vector2i(x,y)
					if not _buckets.has(key):
						_buckets[key] = []
					_buckets[key].append(segment)

func cells(origin: Vector2, size: float, resolution: int) -> Dictionary:
	var result := {}
	var seen := {}
	var finish := origin+Vector2.ONE*size
	var step := size/resolution
	for by in range(floori(origin.y/BUCKET_SIZE),floori(finish.y/BUCKET_SIZE)+1):
		for bx in range(floori(origin.x/BUCKET_SIZE),floori(finish.x/BUCKET_SIZE)+1):
			for segment in _buckets.get(Vector2i(bx,by),[]):
				var a: Vector3 = segment.a
				var b: Vector3 = segment.b
				var identity := [a,b]
				if seen.has(identity):
					continue
				seen[identity] = true
				var lower: Vector2 = (segment.lower-origin)/step
				var upper: Vector2 = (segment.upper-origin)/step
				for cy in range(maxi(0,floori(lower.y)),mini(resolution,floori(upper.y)+1)):
					for cx in range(maxi(0,floori(lower.x)),mini(resolution,floori(upper.x)+1)):
						var key := Vector2i(cx,cy)
						if not result.has(key):
							result[key] = []
						result[key].append(segment)
	return result

func corrected_height(point: Vector3, segments: Array = []) -> float:
	var candidates: Array = segments
	if candidates.is_empty():
		candidates = _buckets.get(Vector2i(floori(point.x/BUCKET_SIZE),floori(point.z/BUCKET_SIZE)),[])
	var result := point.y
	var location := Vector2(point.x,point.z)
	for segment in candidates:
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		var from := Vector2(a.x,a.z)
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf((location-from).dot(delta)/delta.length_squared(),0.0,1.0)
		var distance := location.distance_to(from+delta*t)
		if distance>half_width+blend_width:
			continue
		var weight := 1.0-smoothstep(half_width,half_width+blend_width,distance)
		var floor_y := lerpf(a.y,b.y,t)-clearance
		result = minf(result,lerpf(point.y,floor_y,weight))
	return result

func add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3, segments: Array, chunk_size: float = 80000.0, depth: int = 0) -> void:
	var lower := Vector2(a.x,a.z).min(Vector2(b.x,b.z)).min(Vector2(c.x,c.z))+Vector2(center.x,center.z)
	var upper := Vector2(a.x,a.z).max(Vector2(b.x,b.z)).max(Vector2(c.x,c.z))+Vector2(center.x,center.z)
	var nearby: Array = []
	for segment in segments:
		if segment.lower.x<=upper.x and segment.upper.x>=lower.x and segment.lower.y<=upper.y and segment.upper.y>=lower.y:
			nearby.append(segment)
	if not nearby.is_empty() and depth<8 and maxf(a.distance_to(b),maxf(b.distance_to(c),c.distance_to(a)))>edge_limit:
		var ab := (a+b)*0.5
		var bc := (b+c)*0.5
		var ca := (c+a)*0.5
		add_triangle(surface,a,ab,ca,center,nearby,chunk_size,depth+1)
		add_triangle(surface,ab,b,bc,center,nearby,chunk_size,depth+1)
		add_triangle(surface,ca,bc,c,center,nearby,chunk_size,depth+1)
		add_triangle(surface,ab,bc,ca,center,nearby,chunk_size,depth+1)
		return
	for original in [a,b,c]:
		var vertex: Vector3 = original
		if not nearby.is_empty():
			vertex.y = corrected_height(vertex+center,nearby)-center.y
		surface.set_uv(Vector2(vertex.x,vertex.z)/chunk_size+Vector2(0.5,0.5))
		surface.add_vertex(vertex)
