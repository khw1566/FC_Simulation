extends RefCounted
## 분할 캐시 원본 일치 판정. git pull·체크아웃은 내용이 같아도 수정 시각을 바꾸므로
## 시각이 다르면 SHA-256으로 재확인하고, 확인된 시각을 user://에 기억해 다음 실행의 해시 계산을 생략한다.

const RECORD_PATH := "user://source_signature_verified.cfg"

static func matches(path: String, length: int, expected_size: int, expected_time: int, expected_hash: String) -> bool:
	if length != expected_size:
		return false
	var modified := FileAccess.get_modified_time(path)
	if modified > 0 and modified == expected_time:
		return true
	if expected_hash.is_empty():
		return false
	var record := ConfigFile.new()
	record.load(RECORD_PATH)
	var key := path.md5_text()
	if modified > 0 and int(record.get_value(expected_hash, key, -1)) == modified:
		return true
	if FileAccess.get_sha256(path) != expected_hash:
		return false
	if modified > 0:
		record.set_value(expected_hash, key, modified)
		record.save(RECORD_PATH)
	return true
