# 게임 실행 파일과 개발 자료 분리
게임 실행에 필요한 프로젝트는 `godot_project/`, 실행 진입점은 루트의 `run_game.bat`이다. 실행에 사용하는 Godot 엔진은 `tools/godot/`에 보존한다.

- `build_artifacts/work/`: 이전 Windows 빌드 작업 복사본과 임포트 캐시.
- `build_artifacts/releases/`: 이전 배포 EXE, PCK, ZIP 및 패키지 설명서.
- `build_artifacts/processed/`: 파이프라인 중간 처리 자료.
- `build_artifacts/logs/`: 루트에 흩어진 Godot 로그.
- `source_assets/raw/`: 수집 원본 자료.
- `source_assets/archives/`: 압축 보관 원본과 복원 매니페스트.
- `source_assets/기초 미가공데이터/`: 수동으로 확보한 DEM과 수치지도 원본.

원본 자료와 처리 자료의 기존 경로에는 Windows 디렉터리 정션을 남긴다. 정션은 같은 자료를 가리키는 연결이며 복사본이 아니다. 기존 수집·가공·복원 도구와 매니페스트의 경로를 유지한다. 폴더를 다른 PC로 복사할 때에는 실제 `source_assets/`와 `build_artifacts/processed/`를 함께 보존하고 필요하면 정션을 다시 만든다.

`godot_project/assets/`의 모델·지도·텍스처·씬은 게임 실행용 자산이므로 이동하지 않는다. 에셋 색인 및 자산 매니페스트 갱신 대상인 실행용 자산의 추가·수정·삭제는 수행하지 않는다. `previews/`는 독립 프리뷰 전용 경로 유지 규칙에 따라 보존한다. 소스 코드, 개발 문서, 가상환경과 원본 프로젝트의 엔진 캐시도 보존한다.

후속 Windows 빌드는 `pipeline/packaging/build_windows.py`를 사용하면 `build_artifacts/` 안에 생성된다. `261012_FileSeparation.json`에 각 이동의 파일 수·용량·검증 상태를 기록한다. 파일 삭제와 전체 게임 실행은 수행하지 않는다. 검증은 이동 파일의 크기와 수정시각 비교 및 연결 경로 확인으로 한정한다.
