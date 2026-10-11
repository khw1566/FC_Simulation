extends RefCounted
class_name StreamFrameBudget

## 여러 스트리밍 작업이 공유하는 메인 스레드 업로드 예산.
const USEC := 2000
const MAX_SUBMITS := 16
static var _frame := -1
static var _started := 0
static var _count := 0
static var _peak_usec := 0
static var _peak_at := 0
static var submitted := 0

static func can_submit() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_started = Time.get_ticks_usec()
		_count = 0
	return _count<MAX_SUBMITS and Time.get_ticks_usec()-_started<USEC

static func wait(owner: Node) -> bool:
	while is_instance_valid(owner) and owner.is_inside_tree():
		if can_submit():
			return true
		await owner.get_tree().process_frame
	return false

static func record(started: int) -> void:
	_count += 1
	submitted += 1
	var now := Time.get_ticks_usec()
	var duration := now-started
	if now-_peak_at>2000000:
		_peak_usec = 0
	if duration>=_peak_usec:
		_peak_usec = duration
		_peak_at = now

static func recent_peak_ms() -> float:
	return _peak_usec/1000.0 if Time.get_ticks_usec()-_peak_at<=2000000 else 0.0
