# FC_Simulation

게임 실행은 `run_game.bat`를 사용한다. 게임 프로젝트와 실행용 자산은 `godot_project/`에 있다.

- `build_artifacts/`: 빌드 작업본, 과거 배포 패키지, 중간 처리 자료와 로그.
- `source_assets/`: 수집 원본, 원본 압축 보관본과 수동 확보 자료.
- `pipeline/`, `config/`, `tools/`: 소스 코드, 생성 설정과 개발 도구. 실행에 필요한 엔진은 `tools/godot/`에 유지한다.
- `previews/`: 독립 자산 프리뷰. 기존 경로를 유지한다.
- 정리 내역과 연결 경로 설명: [파일 분리 기록](results/261012_FileSeparation.md).
