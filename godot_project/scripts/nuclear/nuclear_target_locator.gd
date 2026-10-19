extends RefCounted
class_name NuclearTargetLocator

## 카메라 시선과 지형의 교차점을 높이맵 표본으로 찾는다. 물리 충돌이 아직 없는 원경 청크에서도 동작한다.
## 해수면 아래 지형은 수면(0m)으로 본다.

const MAX_RANGE := 70000.0

static func locate(camera: Camera3D, terrain: Node, fallback_distance: float) -> Vector3:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	if _has_terrain(terrain):
		var step := 40.0
		var prev_t := 0.0
		var t := step
		while t < MAX_RANGE:
			var p := origin + dir * t
			if p.y <= ground_height(terrain, p.x, p.z):
				var lo := prev_t
				var hi := t
				for _i in range(14):
					var mid := (lo + hi) * 0.5
					var q := origin + dir * mid
					if q.y <= ground_height(terrain, q.x, q.z):
						hi = mid
					else:
						lo = mid
				var hit := origin + dir * hi
				return Vector3(hit.x, ground_height(terrain, hit.x, hit.z), hit.z)
			prev_t = t
			step = minf(step * 1.08, 600.0)
			t += step
	# 하늘을 보고 있으면 수평 전방 기본 거리에 떨어뜨린다.
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var p2 := origin + flat * fallback_distance
	return Vector3(p2.x, ground_height(terrain, p2.x, p2.z), p2.z)

static func ground_height(terrain: Node, x: float, z: float) -> float:
	if _has_terrain(terrain):
		return maxf(float(terrain.call("get_terrain_elevation", x, z)), 0.0)
	return 0.0

static func is_water(terrain: Node, point: Vector3) -> bool:
	if terrain and terrain.has_method("get_water_mask"):
		if float(terrain.call("get_water_mask", point.x, point.z)) > 0.5:
			return true
	return point.y <= 0.5

## 두 점 사이 직선이 지형에 가리지 않는지 몇 개 표본으로 확인한다(화구 눈부심 가림용).
static func line_clear(terrain: Node, from: Vector3, to: Vector3, samples: int) -> bool:
	if not _has_terrain(terrain):
		return true
	for i in range(1, samples):
		var p := from.lerp(to, float(i) / float(samples))
		if p.y < ground_height(terrain, p.x, p.z) - 5.0:
			return false
	return true

static func _has_terrain(terrain: Node) -> bool:
	return terrain != null and terrain.has_method("get_terrain_elevation")
