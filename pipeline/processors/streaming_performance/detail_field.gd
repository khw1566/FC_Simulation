extends RefCounted
var curved := false
func corrected_height(point: Vector3) -> float:
	return point.y+(0.1*sin(point.x*PI/8.0) if curved else 0.0)
