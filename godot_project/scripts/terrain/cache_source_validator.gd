extends RefCounted

## PCK 내부에는 수정 시각이 없으므로 원본 내용 해시로 캐시를 검증한다.
## 같은 원본(약 200MB 지도 벡터 등)을 여러 관리자가 검사하므로 실행 중 해시는 한 번만 계산한다.
static var _hashes: Dictionary = {}
static var _mutex := Mutex.new()

static func matches(path: String, metadata: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(metadata.get("source_size", -1)):
		return false
	file.close()
	var modified := FileAccess.get_modified_time(path)
	if modified > 0:
		return modified == int(metadata.get("source_modified", -1))
	var expected := str(metadata.get("source_sha256", ""))
	return not expected.is_empty() and sha256(path) == expected

static func sha256(path: String) -> String:
	_mutex.lock()
	var cached: String = _hashes.get(path, "")
	_mutex.unlock()
	if not cached.is_empty():
		return cached
	var digest := FileAccess.get_sha256(path)
	_mutex.lock()
	_hashes[path] = digest
	_mutex.unlock()
	return digest
