extends Node
class_name NuclearCloudInteraction

## 활성 핵폭발(최신 순 최대 4건)의 상태를 기존 구름층 셰이더의 blast_* 배열로 전달한다.
## 구름층은 이를 받아 소산 구멍·충격파 응결·섬광 조명·버섯구름 가림을 적용하고,
## 광학 패스(구름 그림자·빛줄기)는 구름 관리자의 공유 유니폼 복사로 같은 값을 받는다.

const MAX_BLASTS := 4
const KEYS := ["blast_a", "blast_b", "blast_c", "blast_d", "blast_e", "blast_f"]

var cloud_manager: Node
var _was_active := false

func push(detonations: Array) -> void:
	if not cloud_manager or not cloud_manager.has_method("set_blast_uniforms"):
		return
	var count := mini(detonations.size(), MAX_BLASTS)
	if count == 0 and not _was_active:
		return
	var rows: Array = []
	for _k in range(KEYS.size()):
		var row := PackedVector4Array()
		row.resize(MAX_BLASTS)
		rows.append(row)
	for i in range(count):
		var values: Array = detonations[detonations.size() - 1 - i].cloud_uniform_row()
		for k in range(KEYS.size()):
			var row: PackedVector4Array = rows[k]
			row[i] = values[k]
			rows[k] = row
	var uniforms := {"blast_count": count}
	for k in range(KEYS.size()):
		uniforms[KEYS[k]] = rows[k]
	cloud_manager.call("set_blast_uniforms", uniforms)
	_was_active = count > 0
