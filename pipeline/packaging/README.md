# Windows 패키징
원본 게임 프로젝트를 `.build`에 복사한 뒤 복사본에서만 임포트한다. 원본의 `.godot`나 `.import`는 변경하지 않는다. Godot 4.3 엔진과 원본 데이터·임포트 결과를 포함한 PCK를 `dist`에 출력한다.

```powershell
& '.\.venv_campus\Scripts\python.exe' pipeline/packaging/build_windows.py
```

기존 산출물이 있으면 덮어쓰지 않고 중단한다. 다른 버전은 `--version FC_Simulation_20261005_windows_x64_v2`처럼 지정한다. 지도 선택 메뉴 시작만 확인하며 전체 맵은 실행하지 않는다. 배포 폴더에는 실행파일·PCK·실행 배치파일·해시 매니페스트를 포함하고 ZIP도 생성한다. 빌드·배포·프리뷰 캐시는 Git에 포함하지 않는다.
