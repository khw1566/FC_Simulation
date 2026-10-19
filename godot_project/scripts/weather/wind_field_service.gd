extends Node
class_name WindFieldService

## 3차원 바람장: 고도별 대기 바람 단면(대기 상태 모델) + 펄린 노이즈 편차(수평·연직 3성분) + 등록된 국지 교란.
## 국지 교란(핵폭발 대류 등)이 생기면 영향 범위 칸의 벡터에 교란 벡터를 더해 격자 데이터를 교체한다.
## 격자 합성은 작업 스레드에서 주기적으로 수행하고, 끝나면 CPU 표본 데이터와 구름 셰이더용 3D 텍스처(이전·현재 2장)를 바꾼다.

signal field_updated

const Grid := preload("res://scripts/weather/wind_field_grid.gd")
const AtmosphereStateModelClass := preload("res://scripts/models/atmosphere_state_model.gd")
const SurfaceClimateModelClass := preload("res://scripts/models/surface_climate_model.gd")
const FALLBACK_WIND := Vector3(8.0, 0.0, 4.0)
# 펄린 잡음 규모(m): 수평 약 18km, 연직 약 4.5km 크기의 바람 덩어리
const NOISE_SCALE := Vector3(18000.0, 4500.0, 18000.0)

@export var weather_manager: Node
## 격자 재합성 주기(s). 셰이더는 이 간격 동안 이전·현재 텍스처를 보간한다.
@export var refresh_interval := 1.0
## 고도별 바람 단면(날씨·시각) 재계산 주기(s)
@export var profile_interval := 30.0
## 수평 편차 = 풍속 × 비율과 하한 중 큰 값(m/s)
@export_range(0.0, 1.0) var turbulence_ratio := 0.3
@export var turbulence_floor := 1.5
## 지면 근처 연직 편차(m/s). 고도가 높을수록 줄어든다.
@export var vertical_turbulence := 0.8

var _profile := PackedVector3Array()
var _noise := PackedVector3Array()
var _composed := PackedVector3Array()
var _events := {}
var _next_id := 1
var _task_id := -1
var _task_job := {}
var _texture_prev: ImageTexture3D
var _texture_curr: ImageTexture3D
var _since_swap := 0.0
var _refresh_timer := 0.0
var _profile_timer := 0.0

func _ready() -> void:
	if not weather_manager:
		weather_manager = get_parent()
	_profile = _compute_profile()
	_start_task()

func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

func is_field_ready() -> bool:
	return _texture_curr != null

## 월드 위치의 바람 벡터(m/s, y는 연직 성분)
func sample(pos: Vector3) -> Vector3:
	if _composed.size() == Grid.count():
		return Grid.sample(_composed, pos)
	return _profile_at(pos.y)

## 국지 교란 등록. 반환한 id로 갱신·제거한다.
func register_perturbation(perturbation: RefCounted, params: Dictionary) -> int:
	var id := _next_id
	_next_id += 1
	_events[id] = {"perturbation": perturbation, "params": params.duplicate(true)}
	return id

func update_perturbation(id: int, params: Dictionary) -> void:
	if _events.has(id):
		_events[id]["params"] = params.duplicate(true)

func remove_perturbation(id: int) -> void:
	_events.erase(id)

## 구름 밀도장(wind_field.gdshaderinc) 유니폼
func shader_state() -> Dictionary:
	var ready := _texture_curr != null
	return {
		"wind_field_active": ready,
		"wind_field_prev": _texture_prev if ready else null,
		"wind_field_curr": _texture_curr if ready else null,
		"wind_field_origin": Grid.ORIGIN,
		"wind_field_cell": Grid.CELL,
		"wind_field_dims": Grid.texture_dims(),
		"wind_field_blend": clampf(_since_swap / maxf(refresh_interval, 0.05), 0.0, 1.0),
	}

func _process(delta: float) -> void:
	_since_swap += delta
	_profile_timer += delta
	if _profile_timer >= profile_interval:
		_profile_timer = 0.0
		_profile = _compute_profile()
	if _task_id >= 0:
		if WorkerThreadPool.is_task_completed(_task_id):
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = -1
			_apply_result()
		return
	_refresh_timer += delta
	if _refresh_timer >= refresh_interval:
		_refresh_timer = 0.0
		_start_task()

func _start_task() -> void:
	var events: Array = []
	for id in _events:
		var entry: Dictionary = _events[id]
		var params: Dictionary = entry.params
		events.append({"perturbation": entry.perturbation, "params": params.duplicate(true), "bounds": entry.perturbation.bounds(params)})
	_task_job = {
		"profile": _profile,
		"noise": _noise,
		"events": events,
		"amp": Vector3(turbulence_ratio, turbulence_floor, vertical_turbulence),
	}
	_task_id = WorkerThreadPool.add_task(_compose.bind(_task_job), false, "WindFieldCompose")

## 작업 스레드: 기본장(단면 + 펄린 편차)에 교란 벡터를 더해 격자와 텍스처 이미지를 만든다.
func _compose(job: Dictionary) -> void:
	var noise: PackedVector3Array = job.noise
	if noise.size() != Grid.count():
		noise = _build_noise()
	var profile: PackedVector3Array = job.profile
	var events: Array = job.events
	var amp: Vector3 = job.amp
	var composed := PackedVector3Array()
	composed.resize(Grid.count())
	for iy in range(Grid.NY):
		var prof := profile[iy]
		var alt := Grid.level_altitude(iy)
		var amp_h := maxf(prof.length() * amp.x, amp.y)
		var amp_v := amp.z * exp(-alt / 3000.0) + 0.1
		var scale := Vector3(amp_h, amp_v, amp_h)
		var layer_events: Array = []
		for e in events:
			var box: AABB = e.bounds
			if alt >= box.position.y and alt <= box.end.y:
				layer_events.append(e)
		for iz in range(Grid.NZ):
			for ix in range(Grid.NX):
				var i := Grid.index(ix, iy, iz)
				var v := prof + noise[i] * scale
				if not layer_events.is_empty():
					var pos := Grid.cell_position(ix, iy, iz)
					for e in layer_events:
						var box: AABB = e.bounds
						if box.has_point(pos):
							v += e.perturbation.vector_at(e.params, pos)
				composed[i] = v
	job["result_noise"] = noise
	job["result_composed"] = composed
	job["result_images"] = Grid.to_images(composed)

func _apply_result() -> void:
	if not _task_job.has("result_composed"):
		return
	_noise = _task_job.result_noise
	_composed = _task_job.result_composed
	var texture := ImageTexture3D.new()
	texture.create(Image.FORMAT_RGBAH, Grid.NX, Grid.NZ, Grid.NY, false, _task_job.result_images)
	_texture_prev = _texture_curr if _texture_curr else texture
	_texture_curr = texture
	_since_swap = 0.0
	_task_job = {}
	field_updated.emit()

## 칸마다 -1~1 범위의 3성분 펄린 편차(정적 공간 무늬)
func _build_noise() -> PackedVector3Array:
	var layers: Array[FastNoiseLite] = []
	for seed_value in [41201, 77319, 15583]:
		var n := FastNoiseLite.new()
		n.seed = seed_value
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = 1.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		layers.append(n)
	var out := PackedVector3Array()
	out.resize(Grid.count())
	for iy in range(Grid.NY):
		for iz in range(Grid.NZ):
			for ix in range(Grid.NX):
				var q := Grid.cell_position(ix, iy, iz) / NOISE_SCALE
				var v := Vector3(layers[0].get_noise_3dv(q), layers[1].get_noise_3dv(q), layers[2].get_noise_3dv(q)) * 1.4
				out[Grid.index(ix, iy, iz)] = v.clamp(Vector3(-1.0, -1.0, -1.0), Vector3.ONE)
	return out

## 고도 층별 평균 바람(대기 상태 모델: 지면 마찰층 → 제트기류)
func _compute_profile() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(Grid.NY)
	var has_weather := weather_manager != null and ("current_weather" in weather_manager)
	var weather_type := int(weather_manager.get("current_weather")) if has_weather else 2
	var hour: float = SurfaceClimateModelClass.resolve_hour(weather_manager) if has_weather else -1.0
	for iy in range(Grid.NY):
		var alt := Grid.level_altitude(iy)
		if has_weather:
			var state = AtmosphereStateModelClass.calculate_at_altitude(alt, 0.0, weather_type, hour)
			out[iy] = state.wind_vector
		else:
			out[iy] = FALLBACK_WIND * (1.0 + minf(alt / 3000.0, 3.0))
	return out

func _profile_at(altitude: float) -> Vector3:
	if _profile.size() != Grid.NY:
		return FALLBACK_WIND
	var f := clampf(altitude / Grid.CELL.y, 0.0, float(Grid.NY - 1) - 0.0001)
	var i := int(f)
	return _profile[i].lerp(_profile[i + 1], f - float(i))
