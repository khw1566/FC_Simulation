extends RefCounted
class_name WindPerturbation

## 바람장에 더해지는 국지 교란의 공통 형식(폭발 대류, 이후 화재·폭풍 세포 등).
## 바람장은 격자 합성 시 영향 범위 안의 칸에 vector_at 결과를 덧셈으로 반영한다.
## params는 작업 스레드로 복사되는 값 사전이므로 노드나 리소스를 담지 않는다.

func bounds(_params: Dictionary) -> AABB:
	return AABB()

func vector_at(_params: Dictionary, _pos: Vector3) -> Vector3:
	return Vector3.ZERO
