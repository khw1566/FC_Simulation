# Windows 패키징
원본 게임 프로젝트를 `build_artifacts/work`에 복사한 뒤 복사본에서만 임포트한다. 원본의 `.godot`나 `.import`는 변경하지 않는다. Godot 4.3 엔진과 원본 데이터·임포트 결과를 포함한 PCK를 `build_artifacts/releases`에 출력한다.

```powershell
& '.\.venv_campus\Scripts\python.exe' pipeline/packaging/build_windows.py
```

기존 산출물이 있으면 덮어쓰지 않고 중단한다. 다른 버전은 `--version FC_Simulation_20261005_windows_x64_v2`처럼 지정한다. 지도 선택 메뉴 시작만 확인하며 전체 맵은 실행하지 않는다. 배포 폴더에는 실행파일·PCK·실행 배치파일·해시 매니페스트를 포함하고 ZIP도 생성한다. 빌드·배포·프리뷰 캐시는 Git에 포함하지 않는다.

Godot 4.3의 PCK 정렬 계산에서 2GB 경계를 넘으면 위치 정보가 어긋날 수 있어, `pack_project.gd`는 정렬값 1로 기록한다. `pck_integrity.PckIntegrity`는 기존 정렬값 32로 생성된 비암호화 PCK의 모든 파일 MD5를 확인한 뒤 위치 색인만 복구하는 도구다. 새 패키징에는 복구가 필요하지 않다. `WindowsPackageBuilder.package(reuse_pck=True)`는 무결성 확인이 끝난 PCK의 시작 검사와 ZIP 생성을 이어가는 내부 진입점이다.

패키징 리포트는 `results/<version>_WindowsPackaging.json`에 저장해 이전 빌드 기록을 덮어쓰지 않는다.

PCK 내부 원본의 수정 시각은 0이므로 지도 분할·경량 지형·터널 공간 캐시는 파일 크기와 SHA256으로 확인한다. 디스크 원본은 기존 크기·시각 검사를 유지한다. 실제 내용이 다른 경량 지형은 원본으로 대체한다.

`PckRevision`은 기존 비암호화 PCK의 내용을 MD5로 확인하면서 지정 파일만 교체한 별도 PCK를 생성한다. `revise_map_loading.py`는 20261012 패키지에 지도 로딩 수정본을 적용하는 전용 진입점이다. 원래 배포 PCK는 덮어쓰지 않는다.

`check_map_loading.gd`는 패키지의 지도 분할 캐시와 잘못된 해시 거부를 확인한다. `-- --load-map`을 추가하면 별도 사용자 데이터 환경에서 울산 80km의 경량 품질 초기 로딩을 최대 180초 확인한다. 실제 렌더러를 사용하며, 기존 게임은 종료하지 않는다. 전체 지도 이동·장시간 실행을 검증하지 않는다.

경량/표준/고품질의 밀집 도로 지형 세분화 최소 간격은 각각 16m/8m/2m다. 고품질은 기존 세분화 정책을 유지한다. 도로 원본·지도 범위·노반 높이 계산은 보존한다. 경량 품질은 좁은 도로 주변 지형의 형상 정밀도를 낮춰 초기 메시 계산을 줄인다.
