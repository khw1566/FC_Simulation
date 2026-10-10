# 태화강 둔치 생태 구역
`taehwagang_dunchi` 지도(8km, 태화강 국가정원~명촌교) 범위의 둔치를 6개 생태 구역으로 나누고, 구역 성격에 맞춰 덩어리 메시·바닥 텍스처·근경 개체로 표현한다. 구역 경계는 OSM 숲·공원 다각형과 설정의 경도 범위·기준 다각형으로 정한 추정값이며 현장 식생도가 아니다. 울산 80km 지도에서도 위경도 변환으로 같은 위치에 표시된다.
## 배치 부지
- 원천 둔치 마스크는 거친 공개 고도에서 만들어져 조각나고 시가지로 번진다. 그래서 서쪽 상류 유입부와 이어진 폭 16m 이상 수면(태화강 본류·동천)에서 잰 연속 띠를 부지로 쓴다. 띠 폭은 기본 70m, 삼호 상류부 60m, 명촌 하류부·동천 120m이며 추정값이다.
- 띠와 맞닿은 수면 300m 이내 OSM 공원·잔디(국가정원 등)를 더하고 20m 닫힘 연산으로 작은 틈을 메운다. 고립된 연못·저수지와 항만 수계는 제외한다.
- 설정: `config/taehwagang_ecozones.json`의 `placeable_repair`.
## 배치 제외(차도·건물·강)
- 게임에 실제로 그려지는 울산 80km 지도 자료(`buildings_and_roads.json`의 도로 폭+2m, 건물 다각형+2m)와 그 지도의 수면 마스크, OSM 차도(등급별 폭+2m), 원천 둔치 수면을 제외 마스크로 만들어 부지에서 뺀다. 게임 자료는 대상 범위만 `data/raw/taehwagang_ecozones/game_obstacles_ulsan_metro_80km.json`에 캐시한다.
- 개체는 흔들린 최종 위치에서 제외 마스크까지 `clearance_m`(대나무 숲 타일 4.5m, 활엽수 3m, 억새 군락 2m 등) 이상 떨어져야 놓인다. 수관 덩어리 셀과 흐림 가장자리도 제외 마스크 위에는 만들지 않는다.
- 실행 시 `EcozoneScatter`가 지형의 수면 마스크로 한 번 더 검사해 강 위 개체를 버린다.
## 억새·갈대 필드(2026-10-10)
- 억새·갈대는 개체 배치 대신 카메라 주변 반경 120m의 GPU 필드로 그린다(`silvergrass_field.gd`, `silvergrass_field.gdshader`). 0.9m 칸마다 18삼각형 다발(꽃대 5·숙인 이삭 5·잎 3)을 스플랫 억새(G)·갈대(A) 비율만큼 세우고, 50m 밖부터 성기게 한다. 위치·회전·크기는 칸 좌표 해시로 고정된다.
- 밑동 높이는 렌더된 지형 청크 LOD와 같은 GPU 높이 함수(`terrain_height.gdshaderinc`, 도로 재질의 지형 높이 값 공유)로 구해 지면에 붙는다.
- 바람은 풍향으로 진행하는 파동(파장 22m, 7m/s)과 직교 돌풍 띠라 들판이 물결치고, 마루에서 이삭이 밝게 반짝인다. 황금빛 꽃대·은금빛 이삭, 갈대 칸은 갈색.
- 반경 밖은 황금빛 억새 바닥 텍스처(150~450m부터 단색·그라데이션)가 이어 받는다. 설정: `ground_blend.silvergrass_field`.
## 구역별 표현
| ID | 구역 | 면적 | 원경 | 근경 |
|---:|---|---:|---|---|
| 3 | 대숲(십리대숲) | 32.2ha | 수관 덩어리 메시(높이 9.5m, 100~125m부터) | 대나무 숲 타일 7m·군집 3.6m 육각, 흔들림, 100~125m에서 사라짐 |
| 5 | 수림대 | 6.9ha | 수관 덩어리 메시(높이 13m, 120~145m부터) | 활엽수 6.5m 육각, 120~145m에서 사라짐 |
| 2 | 억새 군락 | 69.6ha | 지형 바닥 억새 텍스처 | GPU 억새 필드(반경 120m, 물결) |
| 4 | 수변 갈대 | 39.4ha | 지형 바닥 갈대 텍스처 | GPU 필드 갈대색(반경 120m, 물결) |
| 1 | 잔디 광장 | 85.2ha | 지형 바닥 잔디 텍스처 | 개체 없음(텍스처만) |
| 6 | 들풀 초지 | 4.4ha | 지형 바닥 들풀 텍스처 | 관목 14m, 억새 군집 7m |

- 판정 규칙(우선순위 순): 대숲(OSM 숲 12m 버퍼 ∩ 삼호교~태화교 구간, 국가정원 곡류부 안쪽 강변 띠) → 수변 갈대(수면 0~20m) → 수림(OSM 숲·관목) → 억새(명촌 하류부·삼호 상류부 수면 거리 밴드, 습지) → 잔디(OSM 공원·잔디·경기장, 도심 구간) → 들풀(나머지).
- 수관 덩어리: 대숲 35.8ha, 수림 7.0ha. 구역을 12m 닫힘으로 덩어리화하고, 가장자리 10~14m에서 수관이 지면까지 둥글게 내려간다.
- 원경 단색: 바닥은 150~450m, 수관 덩어리는 200~550m 구간에서 텍스처 무늬가 사라지고 텍스처 평균색(최소 밉맵)에 수백 m 규모의 완만한 그라데이션만 남는다.
- 근경 개체와 수관 덩어리는 같은 거리 구간에서 화면 픽셀 단위 디더로 교대한다(`vegetation_sway.gdshader`의 `fade_far_m`, `forest_mass.gdshader`의 `fade_near_m`). 가까이서는 개별 에셋만, 멀리서는 덩어리만 그려 겹치지 않는다.
- 근경 개체 134,087개. 개체는 계열별 거리 안에서만 그리고, 원경은 덩어리 메시와 바닥 텍스처가 맡는다.
## 파일
- `ecozone_labels_8bit.png`: 2048px(약 3.9m), 픽셀값=구역 ID, 0=비대상. 지도 bbox와 같고 0행이 북쪽.
- `ecozone_splat_a_rgba.png`(R 잔디, G 억새, B 대숲 낙엽, A 수변 갈대), `ecozone_splat_b_rgba.png`(R 수림, G 들풀, A 부지): 1.5px 흐림 가중치.
- `ground/*.png`: 512px 반복 텍스처 8종(바닥 6종, 수관 2종).
- `ground_blend.json`: 지형 셰이더 바닥 혼합 설정(스플랫·텍스처 경로, 반복 6m, 6km 밖 페이드).
- `forest_masses.json`: 수관 덩어리 셀 `[열, 행, 높이 비율 0~255]`.
- `scatter_instances.json`: 근경 개체 레이어별 `[x, y, z, yaw_deg, scale]`(원천 지도 월드 미터)와 계열 LOD 거리·흔들림 설정.
- `ecozone_preview.png`, `catalog.json`, `manifest.json`.
## 게임 연결
- `EcozoneScatter`(`res://scripts/vegetation/ecozone_scatter.gd`)가 메인 월드 씬에 있다. 지도 bbox가 겹치면 바닥 혼합 연결(`ecozone_ground_binder.gd` → `procedural_terrain.gdshader`의 `ecozone_blend()`), 수관 덩어리(`forest_mass_builder.gd`), 근경 개체(`vegetation_batch_factory.gd`, `vegetation_sway.gdshader`)를 순서대로 만든다.
- 실제 게임 GPU 프레임은 측정하지 않았다. 근경 개체는 묶음 노드가 많아 지도 로딩 시 잠깐 걸릴 수 있다.
## 재생성
```powershell
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/processors/taehwagang_ecozones/generate.py
```
- 원천 둔치 산출물은 `godot_project/assets/maps/taehwagang_dunchi`, 없으면 `../FC_Simulation_dunchi/...`에서 읽기 전용으로 찾는다.
- `--refresh-osm`: OSM 식생·공원 캐시(`data/raw/taehwagang_ecozones/osm_landcover.json`)를 다시 받는다.
