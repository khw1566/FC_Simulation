# 태화강 둔치 보도 배치
둔치 지형 스레드의 OSM 보행로 선형(`roads_raw.json`)과 둔치 배치 가능·수면 마스크로 태화강 둔치 보도와 벤치를 배치한 결과다. 현재 지도에서는 `RiversideTrialPlacer`가 읽는다.
## 구성
- `paths.json`: 보도 체인 178개, 조각 2,847개. 체인마다 약 12 m 간격 접속점 위경도와 보도 씬을 가진다.
- `placements.json`: 보도 옆 벤치 235개. `taehwagang_dunchi` 지도 `placements.json`과 같은 형식이다.
- `preview.png`: 전체 둔치 평면도. 진회색 수면, 연회색 둔치, 검은 선 보도, 점 벤치.
- `manifest.json`: 원자료 경로, 유형별 길이, 파일 해시.
## 선정과 형태
- 보행로·자전거길·보행자 도로 중 둔치 마스크를 40 m 넓힌 권역 안에 60% 이상 있는 선형만 쓴다. 수면 위, 교량, 터널, 광장 면형은 뺀다.
- 포장 태그가 있으면 그 재질(아스팔트, 자갈, 목재 데크 등)을, 없으면 유형별 기본값을 쓴다. 국가정원 구간 보도는 적갈색 블록, 자전거길은 공유길이다.
- 게임에서는 이웃 조각이 접속점 높이를 공유하고 조각 폭 전체가 지형 위에 오도록 올린다. 굽은 접속부는 조각 끝을 0.6 m씩 겹쳐 틈을 덮는다.
- 같은 씬은 400 m 격자별 MultiMesh로 묶고 3 km 밖은 그리지 않는다.
## 재생성
```powershell
python -m pipeline.processors.riverside_paths.build_riverside_paths
```
기본 입력은 옆 작업 폴더 `FC_Simulation_dunchi`의 둔치 지도와 `data/raw/taehwagang_dunchi/roads_raw.json`이다. 조건은 `config/riverside_paths.json`에서 바꾼다. 예전 3곳 시범 배치 생성기(`pipeline/processors/riverside_trial/build_trial_placements.py`)는 같은 `placements.json`을 덮어쓰므로 다시 실행하지 않는다.
