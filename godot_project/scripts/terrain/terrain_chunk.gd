extends Node3D
class_name TerrainChunk

signal chunk_loaded(chunk_coord: Vector2i)

var chunk_coord: Vector2i
var chunk_world_size: float
var chunk_center: Vector3
var current_lod: int = -1
var _lod_mesh_cache: Dictionary = {}

var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

var heightmap_image: Image
var elev_min: float
var elev_max: float
var railway_grader: RefCounted
var road_grader: RefCounted
var base_resolution := 128
const Mesher = preload("res://scripts/terrain/terrain_chunk_mesher.gd")
const Upload = preload("res://scripts/terrain/terrain_mesh_upload.gd")
var _upload: RefCounted
var _task_id := -1
# 저사양 CPU에서 여러 청크를 동시에 계산하면 메인·렌더 스레드가 밀려 끊기므로 동시 계산 수를 제한한다.
# 로딩 화면에서는 관리자가 값을 올려 첫 메시를 병렬로 만든다.
static var max_concurrent_builds := 1
static var _active_builds := 0
var _pending_lod := -1
var _requested_lod := -1
var _result: Dictionary = {}
var _collision_shape_resource: Shape3D
var _collision_step := 1.0

# LOD 레벨별 버텍스 그리드 해상도 (2의 거듭제곱) - 노트북/데스크탑 최적화
const LOD_RESOLUTIONS: Dictionary = {
	0: 128, # 근거리 고해상도 (타일당 128x128 버텍스)
	1: 64,  # 중거리 (타일당 64x64 버텍스)
	2: 32   # 원거리 (타일당 32x32 버텍스)
}

func init_chunk(coord: Vector2i, size: float, center_pos: Vector3, img: Image, min_h: float, max_h: float) -> void:
	chunk_coord = coord
	chunk_world_size = size
	chunk_center = center_pos
	position = center_pos
	heightmap_image = img
	elev_min = min_h
	elev_max = max_h

## 캐시에 있으면 즉시 바꾸고, 없으면 작업 스레드에 메시 계산을 맡긴다.
## 계산이 끝날 때까지 기존 메시를 유지하며 poll_build()가 결과를 적용한다.
func update_lod(target_lod: int, shader_mat: Material) -> void:
	if target_lod == (_pending_lod if is_building() else current_lod):
		if is_building():
			_requested_lod = -1
		return
	if is_building():
		_requested_lod = target_lod
		return
	if not LOD_RESOLUTIONS.has(target_lod) or _lod_mesh_cache.has(target_lod):
		current_lod = target_lod
		_apply_cached(shader_mat)
		return
	if _active_builds >= max_concurrent_builds:
		# 계산 자리가 없으면 다음 LOD 갱신 주기에 다시 요청된다.
		return
	_start_build(target_lod)

## 검사·베이크 도구용: 결과가 나올 때까지 기다려 즉시 적용한다.
func update_lod_now(target_lod: int, shader_mat: Material) -> void:
	update_lod(target_lod, shader_mat)
	while is_building():
		# 작업 ID는 poll_build()가 회수하므로 여기서는 완료만 기다린다.
		while _task_id>=0 and not WorkerThreadPool.is_task_completed(_task_id):
			OS.delay_usec(200)
		poll_build(shader_mat,true)

func is_building() -> bool:
	return _task_id >= 0 or _upload!=null

## 계산이 끝났으면 메시를 적용하고 true를 반환한다.
func poll_build(shader_mat: Material, immediate: bool = false) -> bool:
	if _upload==null:
		if _task_id<0 or not WorkerThreadPool.is_task_completed(_task_id):
			return false
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_upload = Upload.new()
		_upload.begin(self,_result.pages,shader_mat)
	if not _upload.step(immediate):
		return false
	var lod := _pending_lod
	_pending_lod = -1
	_lod_mesh_cache[lod] = _upload.container
	_upload = null
	_active_builds -= 1
	if _result.has("heights"):
		var shape := HeightMapShape3D.new()
		shape.map_width = int(_result.grid_res) + 1
		shape.map_depth = int(_result.grid_res) + 1
		shape.map_data = _result.heights
		_collision_shape_resource = shape
		_collision_step = float(_result.step)
	_result = {}
	current_lod = lod
	_apply_cached(shader_mat)
	if _requested_lod >= 0 and _requested_lod != current_lod:
		var next := _requested_lod
		_requested_lod = -1
		update_lod(next, shader_mat)
	return true

func _start_build(lod: int) -> void:
	_pending_lod = lod
	_requested_lod = -1
	_active_builds += 1
	var request := {"image": heightmap_image, "grid_res": base_resolution >> lod, "size": chunk_world_size, "center": chunk_center,
		"elev_min": elev_min, "elev_max": elev_max, "grader": railway_grader if lod == 0 else null,
		"road_grader": road_grader if lod == 0 else null,
		"upload_pages": true,
		"collision": lod == 0 and _collision_shape_resource == null}
	_task_id = WorkerThreadPool.add_task(func(): _result = Mesher.compute(request), false, "지형 청크 LOD")

func _apply_cached(shader_mat: Material) -> void:
	if not LOD_RESOLUTIONS.has(current_lod):
		# 범위 밖 (너무 먼 거리)일 경우 메쉬 제거
		for container in _lod_mesh_cache.values():
			container.visible = false
		if collision_shape:
			collision_shape.disabled = true
		return
	for lod in _lod_mesh_cache:
		var container: Node3D = _lod_mesh_cache[lod]
		container.visible = lod==current_lod
		if lod==current_lod:
			for child: MeshInstance3D in container.get_children():
				child.material_override = shader_mat
	mesh_instance = _lod_mesh_cache[current_lod].get_child(0)
	# LOD 0(최근접 청크)에서만 정밀 물리 충돌체를 사용한다.
	if current_lod == 0 and _collision_shape_resource != null:
		if not collision_body:
			collision_body = StaticBody3D.new()
			collision_shape = CollisionShape3D.new()
			collision_body.add_child(collision_shape)
			add_child(collision_body)
		if collision_shape.shape == null:
			# 높이 격자 한 칸을 1m로 보는 형상이므로 격자 간격만큼 수평으로 늘린다.
			collision_shape.scale = Vector3(_collision_step, 1.0, _collision_step)
			collision_shape.shape = _collision_shape_resource
		collision_shape.disabled = false
	elif collision_shape:
		collision_shape.disabled = true

func _exit_tree() -> void:
	var building := is_building()
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	if building:
		_active_builds -= 1
	_upload = null

## 사전 베이크 도구는 모든 렌더 메시를 읽어 대형 청크의 추가 페이지도 보존한다.
func get_render_meshes() -> Array:
	return _lod_mesh_cache[current_lod].get_children() if _lod_mesh_cache.has(current_lod) else []

# 높이맵 픽셀 계단현상(Aliasing / Blockiness) 방지를 위한 3차 에르미트(Smoothstep Cubic) 보간 함수
func get_surface_height(world_x: float, world_z: float) -> float:
	var resolution: int = base_resolution >> clampi(current_lod, 0, 2)
	var uv := (Vector2(world_x-chunk_center.x,world_z-chunk_center.z)/chunk_world_size+Vector2(0.5,0.5)).clamp(Vector2.ZERO,Vector2.ONE)
	var grid := uv*resolution
	var cell := grid.floor().min(Vector2.ONE*(resolution-1))
	var f := grid-cell
	var w := heightmap_image.get_width()
	var h := heightmap_image.get_height()
	var a := _sample_bilinear(cell.x/resolution,cell.y/resolution,w,h)
	var b := _sample_bilinear((cell.x+1)/resolution,cell.y/resolution,w,h)
	var c := _sample_bilinear(cell.x/resolution,(cell.y+1)/resolution,w,h)
	var d := _sample_bilinear((cell.x+1)/resolution,(cell.y+1)/resolution,w,h)
	var value := a+f.x*(b-a)+f.y*(c-a) if f.x+f.y<=1 else d+(1-f.x)*(c-d)+(1-f.y)*(b-d)
	var height := elev_min+value*(elev_max-elev_min)
	if road_grader and current_lod == 0:
		height = road_grader.corrected_height(Vector3(world_x,height,world_z))
	return railway_grader.corrected_height(Vector3(world_x,height,world_z)) if railway_grader and current_lod == 0 else height

func _sample_bilinear(u: float, v: float, w: int, h: int) -> float:
	return Mesher.sample_bilinear(heightmap_image, u, v, w, h)
