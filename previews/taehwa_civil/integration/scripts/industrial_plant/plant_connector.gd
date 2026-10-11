class_name PlantConnector
extends RefCounted
## 3열 배관 포트의 위치와 바깥 방향을 맞춰 모듈을 조립한다.

static func snap(moving: Node3D, moving_port: Marker3D, target_port: Marker3D) -> bool:
	if moving.is_ancestor_of(target_port):
		return false
	if moving_port.get_meta("profile", "") != target_port.get_meta("profile", ""):
		return false
	var a := moving_port.global_transform.basis.get_scale()
	var b := target_port.global_transform.basis.get_scale()
	if not a.is_equal_approx(b) or not is_equal_approx(a.x, a.y) or not is_equal_approx(a.x, a.z):
		return false
	var desired := target_port.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var adjustment := desired * moving_port.global_transform.affine_inverse()
	moving.global_transform = adjustment * moving.global_transform
	return true
