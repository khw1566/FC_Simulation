# 태화강 국가정원·둔치 보도 시범 배치
코덱스 제작 보행로·부속물(`road_assets`)과 정원 시설물(`garden_furniture/near`)을 태화강 둔치 지도에 시범 배치한 결과다. 게임 씬에는 직접 연결하지 않았다.
## 구성
- `placements.json`: `taehwagang_dunchi` 지도 `RiversideAssetPlacer` 스키마(lonlat, ground=terrain)와 같은 형식의 배치 57건
- `preview.png`: 배치 가능 마스크(회색) 위 평면 배치도, 각 칸 140 m, 북쪽이 위
- `manifest.json`: 후보지별 구간 길이, 중심 좌표, 방향, 파일 해시
## 후보지
- garden(태화강 국가정원): 적갈색 블록 보도 120 m, 한쪽 녹지 띠, 벤치, 석재 광장 위 육각 정자
- midstream(중류 둔치): 보행·자전거 공유길 96 m, 평벤치, 천막 아래 피크닉 테이블
- myeongchon(명촌 둔치): 수변 석판 보도 96 m, 피크닉 테이블, 벤치, 행사 천막
## 배치 방식
- 후보지 중심 반경 700 m 안에서 둔치 배치 가능 마스크를 따라 폭 18 m 직선 구간이 가장 길게 이어지는 위치·방향을 찾는다.
- 보도 세그먼트(12 m)를 접속점 간격으로 잇고 시설물을 진행 방향 좌우 오프셋으로 둔다. 높이는 배치기에서 지형 높이에 맞춘다.
- 후보지 중심은 대략 위치이며 실제 시설 배치를 복제하지 않았다. 벤치 정면 방향은 확인하지 않았다.
## 적용
- 둔치 지도의 `assets/maps/taehwagang_dunchi/placements.json` `placements` 배열에 병합하면 배치기가 읽는다.
- 둔치 작업 폴더에는 아직 `road_assets`, `garden_furniture`가 없으므로 함께 복사해야 배치된다. 없으면 배치기가 경고 후 건너뛴다.
## 재생성
```powershell
python -m pipeline.processors.riverside_trial.build_trial_placements --map-dir <taehwagang_dunchi 지도 폴더>
```
후보지와 탐색 조건은 `config/riverside_trial_sites.json`, 레이아웃은 `pipeline/processors/riverside_trial/site_layouts.py`에서 바꾼다.
