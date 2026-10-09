# 태화강 둔치 생태 구역
`taehwagang_dunchi` 지도(8km, 태화강 국가정원~명촌교)의 배치 부지를 6개 생태 구역으로 나누고, 구역마다 규칙 격자로 식생을 배치한 결과다. 구역 경계는 OSM 숲·공원 다각형과 설정의 경도 범위·기준 다각형으로 정한 추정값이며 현장 식생도가 아니다.
## 배치 부지
- 원천 둔치 마스크는 거친 공개 고도에서 만들어져 조각나고 시가지로 번진다. 그래서 서쪽 상류 유입부와 이어진 폭 16m 이상 수면(태화강 본류·동천)에서 잰 연속 띠를 부지로 쓴다. 띠 폭은 기본 70m, 삼호 상류부 60m, 명촌 하류부·동천 120m이며 추정값이다.
- 띠와 맞닿은 수면 300m 이내 OSM 공원·잔디(국가정원 등)를 더하고 20m 닫힘 연산으로 작은 틈을 메운다. 고립된 연못·저수지와 항만 수계는 제외한다.
- 설정: `config/taehwagang_ecozones.json`의 `placeable_repair`.
## 구역
| ID | 구역 | 판정 규칙 (우선순위 순) | 면적 | 배치 |
|---:|---|---|---:|---|
| 3 | 대숲(십리대숲) | OSM 숲 12m 버퍼 ∩ 삼호교~태화교 구간, 국가정원 곡류부 안쪽 강변 띠(수면 8~55m) | 35.4ha | 숲 타일 8m 정사각 격자(내부), 4줄기 군집 3.6m 육각 격자(가장자리 6m) |
| 4 | 수변 갈대 | 수면 0~20m | 57.8ha | 갈대 군락 4.0m 육각 |
| 5 | 수림대 | OSM 숲·관목 | 6.9ha | 활엽수 9m 육각 |
| 2 | 억새 군락 | 명촌 하류부 수면 20~110m(공원 제외), 삼호 상류부 수면 20~70m, 습지 | 113.6ha | 억새 군락 타일 4.2m 육각 |
| 1 | 잔디 광장 | OSM 공원·잔디·경기장, 도심 구간 나머지 | 102.7ha | 가로수형 수목 32m 육각(가장자리 10m 제외) |
| 6 | 들풀 초지 | 나머지 둔치 | 9.9ha | 관목 14m, 억새 군집 7m 육각 |

총 129,438개 인스턴스. 면적과 수량은 2026-10-09 생성 기준이다.
## 파일
- `ecozone_labels_8bit.png`: 2048px(약 3.9m), 픽셀값=구역 ID, 0=비대상. 지도 bbox와 같고 0행이 북쪽.
- `ecozone_splat_a_rgba.png`: R 잔디, G 억새, B 대숲 낙엽, A 수변 갈대 가중치(1.5px 흐림).
- `ecozone_splat_b_rgba.png`: R 수림, G 들풀, A 둔치 평탄면.
- `ground/*.png`: 512px 반복 바닥 텍스처 6종(lawn, silvergrass_ground, bamboo_litter, reed_mud, woodland_soil, meadow).
- `scatter_instances.json`: 레이어별 `[x, y, z, yaw_deg, scale]` 평면 배열. 월드 미터, 지도 중앙 원점, +X 동쪽, +Z 남쪽. y는 생성 시 둔치 높이맵 표본.
- `ecozone_preview.png`: 구역 색과 배치점(1/3 표본) 미리보기.
- `catalog.json`, `manifest.json`: 구역 면적, 레이어 수량, 원천 마스크 해시, OSM 캐시 시각, 파일 해시.
## 게임 연결
- `res://scripts/vegetation/ecozone_scatter.gd`(`EcozoneScatter`) 노드를 월드에 두고 `terrain_manager`를 지정하면 `taehwagang_dunchi` 지도에서만 배치한다. `zones`로 구역을 골라 켤 수 있다. 실행 시 지형 높이로 다시 맞춘다.
- 계열별 LOD 씬은 `vegetation_batch_factory.gd`가 64m 청크 MultiMesh로 묶는다. 전체 배치 시 약 7,800개 묶음 노드가 생기며 거리 범위 밖 묶음은 그리지 않는다. 실제 GPU 프레임 측정은 하지 않았다.
- 바닥 혼합은 `res://shaders/ecozone_ground.gdshaderinc`의 `ecozone_blend()`를 지형 셰이더에서 호출한다. 기존 지형 셰이더에는 아직 연결하지 않았다.
## 재생성
```powershell
& 'C:\Users\work\AppData\Local\Programs\Python\Python312\python.exe' pipeline/processors/taehwagang_ecozones/generate.py
```
- 원천 둔치 산출물은 `godot_project/assets/maps/taehwagang_dunchi`, 없으면 `../FC_Simulation_dunchi/...`에서 읽기 전용으로 찾는다. 둔치 지형을 다시 만들면 이 생성기도 다시 실행한다.
- `--refresh-osm`: OSM 식생·공원 캐시(`data/raw/taehwagang_ecozones/osm_landcover.json`)를 다시 받는다.
- 구역 규칙과 배치 간격은 `config/taehwagang_ecozones.json`에서 바꾼다.
