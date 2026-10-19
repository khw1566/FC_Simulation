extends RefCounted
class_name RoadEarthworkDetail

## 밀집 노반 높이 오차를 검사해 평탄한 삼각형의 균일 세분화를 생략한다.
## 2026-10-19부터 지형 메시 생성은 road_earthwork_mesher.gd의 균일 칸 세분화를 쓰며 이 모듈을 호출하지 않는다.
## 과거 스트리밍 검증 도구(pipeline/processors/streaming_performance/state_check.gd)의 참조용으로만 남긴다.
const MAX_EDGE := 16.0
const MIN_EDGE := 2.0
const HEIGHT_ERROR := 0.12
const EDGE_ERROR := 0.001

static func needs_split(a: Vector3, b: Vector3, c: Vector3, field: RefCounted, candidates: Array, edge: float) -> bool:
	if edge>MAX_EDGE:
		return true
	if edge<=MIN_EDGE:
		return false
	var heights := Vector3(field.corrected_height(a),field.corrected_height(b),field.corrected_height(c))
	# 이웃 삼각형의 세분화 깊이가 달라도 경계 틈이 생기지 않도록,
	# 2m 최저 단계까지 생길 수 있는 경계 정점을 1mm 기준으로 먼저 검사한다.
	for pair in [[a,b,heights.x,heights.y],[b,c,heights.y,heights.z],[c,a,heights.z,heights.x]]:
		for index in range(1,8):
			var fraction := float(index)/8.0
			var point: Vector3 = pair[0].lerp(pair[1],fraction)
			if absf(field.corrected_height(point)-lerpf(pair[2],pair[3],fraction))>EDGE_ERROR:
				return true
	for weights: Vector3 in [Vector3(.5,.5,0),Vector3(0,.5,.5),Vector3(.5,0,.5),Vector3.ONE/3.0]:
		var p := a*weights.x+b*weights.y+c*weights.z
		if absf(field.corrected_height(p)-heights.dot(weights))>HEIGHT_ERROR:
			return true
	var origin := Vector2(a.x,a.z)
	var ab := Vector2(b.x-a.x,b.z-a.z)
	var ac := Vector2(c.x-a.x,c.z-a.z)
	var denominator := ab.cross(ac)
	if absf(denominator)<.00001:
		return false
	var centroid := Vector2((a.x+b.x+c.x)/3.0,(a.z+b.z+c.z)/3.0)
	# 좁은 도로 중심도 검사해 중점 표본 사이의 노반을 놓치지 않는다.
	for s in candidates:
		var from := Vector2(s.a.x,s.a.z)
		var delta := Vector2(s.b.x-s.a.x,s.b.z-s.a.z)
		var t := clampf((centroid-from).dot(delta)/maxf(delta.length_squared(),.001),0.0,1.0)
		var location := from+delta*t
		var ap := location-origin
		var u := ap.cross(ac)/denominator
		var v := ab.cross(ap)/denominator
		if u<0 or v<0 or u+v>1:
			continue
		var weights := Vector3(1-u-v,u,v)
		var p := a*weights.x+b*weights.y+c*weights.z
		if absf(field.corrected_height(p)-heights.dot(weights))>HEIGHT_ERROR:
			return true
	return false
