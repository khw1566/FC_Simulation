# 패키지 지도 로딩 수정

- 사용자 실행 로그에서 울산 80km 지도의 분할 캐시 검사 실패를 확인했다. PCK 내부 파일의 수정 시각 0을 원본 변경으로 판단하던 검사를 크기·SHA256 검사로 보완했다. 디스크 파일의 기존 검사는 유지한다.
- 경량 지형 및 터널 공간 캐시에도 동일한 검사를 적용했다. 현재 경량 높이맵은 원본과 실제 내용이 달라 계속 거부하고 원본 지형을 사용한다. 에셋 생성·수정은 하지 않았으므로 에셋 색인 갱신 대상은 없다.
- 밀집 도로 지형의 최소 세분화 간격을 경량 16m, 표준 8m, 고품질 2m로 구분했다. 고품질 형상 정책과 도로 원본·노반 높이 계산을 유지한다. 경량 품질에서는 좁은 도로 주변 지형 형상 정밀도가 낮아진다.
- 기존 배포 파일과 실행 중인 사용자 게임은 보존했다. 수정본은 `build_artifacts/releases/FC_Simulation_20261012_windows_x64_v2`에 생성한다.

## 확인 범위

- 수정본 PCK의 지도 분할 캐시 3종을 검증했고, 잘못된 SHA256 입력이 거부됨을 확인했다. 기존 파일 내용은 PCK 재작성 중 MD5를 검사했다.
- 현재 PC의 RTX 4070 SUPER, Forward Plus Vulkan, 경량 품질에서 울산 80km 초기 로딩 완료: 35,452ms. 지형 청크 준비 17,014ms. `map_loading_final.log`에 완료 기록이 있다.
- 호환 OpenGL 렌더러 초기 로딩 완료: 31,447ms. 전체 지역 이동, 노트북 성능, 장시간 실행, 표준·고품질 로딩은 미검증이다.
- headless 더미 렌더러는 메시 초기화 중 충돌해 지도 검증 근거로 사용하지 않았다. 긴 진단 캐시 경로의 Vulkan 시험에서는 셰이더 캐시 오류와 엔진 종료도 발생했다. 짧은 별도 캐시 경로의 최종 Vulkan 시험은 오류 없이 완료됐으나, 이전 엔진 종료 원인은 확정하지 않았다. 정상 종료 시 ObjectDB 잔존 객체 경고는 남아 있다.
- 사용자 저장 설정은 고품질이다. 새 패키지는 이 설정을 변경하지 않는다. 빠른 초기 로딩에는 지도 선택 화면에서 경량을 선택한다. 필요하면 `호환모드.bat`를 사용한다.

## 기록

- `build_artifacts/work/FC_Simulation_20261012_windows_x64_v2/pck_revision.json`
- `build_artifacts/work/FC_Simulation_20261012_windows_x64_v2/map_loading_final.log`
- `build_artifacts/work/FC_Simulation_20261012_windows_x64_v2/map_loading_compatibility.log`
- `results/FC_Simulation_20261012_windows_x64_v2_WindowsPackaging.json`
