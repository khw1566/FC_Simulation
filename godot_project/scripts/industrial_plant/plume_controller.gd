extends GPUParticles3D
## 인스턴스별 연기량과 바람. 다른 탑의 재질을 공유 변경하지 않는다.

@export var plume_enabled := true
@export_range(0.0, 1.0) var density := 0.75
@export var wind_velocity := Vector3(2, 0, 0)
@export_range(0.0, 4.0) var buoyancy := 0.35

func _ready() -> void:
	process_material = process_material.duplicate()
	apply_settings()

func apply_settings() -> void:
	emitting = plume_enabled and density > 0.0
	amount_ratio = density
	var material := process_material as ParticleProcessMaterial
	material.gravity = Vector3(wind_velocity.x * 0.18, buoyancy, wind_velocity.z * 0.18)
	# 충분한 가시 영역을 확보하여 풍향 변경 시 갑자기 잘리지 않게 한다.
	var travel := Vector3(absf(wind_velocity.x), 0, absf(wind_velocity.z)) * lifetime * lifetime * 0.09
	visibility_aabb = AABB(Vector3(-30 - travel.x, -8, -30 - travel.z), Vector3(60 + travel.x * 2, 120, 60 + travel.z * 2))
