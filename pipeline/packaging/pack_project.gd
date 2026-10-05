extends SceneTree

## 격리 프로젝트의 임포트 결과와 원본 데이터를 한 PCK에 보관한다.
func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		push_error("파일 목록과 출력 PCK 경로가 필요합니다.")
		quit(1)
		return
	var files = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var packer := PCKPacker.new()
	if packer.pck_start(arguments[1]) != OK:
		quit(1)
		return
	for relative in files:
		var source := "res://" + str(relative)
		if packer.add_file(source, source) != OK:
			push_error("패키지 기록 실패: " + source)
			quit(1)
			return
	if packer.flush() != OK:
		quit(1)
		return
	print("PCK 파일 기록 완료: ", files.size())
	quit()
