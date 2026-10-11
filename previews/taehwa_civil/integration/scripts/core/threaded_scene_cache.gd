extends RefCounted
class_name ThreadedSceneCache

## 키별 PackedScene을 작업 스레드에서 한 번만 만들어 보관한다.
## GLB 해석·씬 생성·충돌 형상 계산이 메인 스레드를 멈추지 않도록 준비 전에는 대기 상태를 돌려준다.
## 실패한 키도 null로 기록하여 같은 실패 읽기를 반복하지 않는다.
var _scenes: Dictionary = {}
var _jobs: Dictionary = {}

## 준비가 끝났으면(실패 포함) true. 처음 요청이면 builder()를 작업 스레드에서 시작한다.
func request(key: String, builder: Callable) -> bool:
	if _scenes.has(key):
		return true
	if not _jobs.has(key):
		var holder := [null]
		var task := WorkerThreadPool.add_task(func(): holder[0] = builder.call(), false, "모델 준비")
		_jobs[key] = {"task": task, "holder": holder}
		return false
	if not WorkerThreadPool.is_task_completed(_jobs[key].task):
		return false
	_finish(key)
	return true

## 검사 도구용: 준비가 끝날 때까지 기다린다.
func request_now(key: String, builder: Callable) -> void:
	if not request(key, builder):
		_finish(key)

## 작업을 회수하고 결과를 기록한다. 회수한 작업 ID는 다시 조회하지 않는다.
func _finish(key: String) -> void:
	var job: Dictionary = _jobs[key]
	WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.erase(key)
	_scenes[key] = job.holder[0] if job.holder[0] is PackedScene else null

## 준비된 씬의 인스턴스. 준비 전이거나 실패했으면 null.
func instantiate(key: String) -> Node:
	var scene: PackedScene = _scenes.get(key)
	return scene.instantiate() if scene else null

## 진행 중인 작업을 모두 회수한다. 소유 노드가 트리에서 빠질 때 호출한다.
func dispose() -> void:
	for job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()
