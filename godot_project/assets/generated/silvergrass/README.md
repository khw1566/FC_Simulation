# 경량 억새·갈대 에셋
억새 단일 군집, 5군집 억새 군락 타일, 4군집 갈대 군락을 제공한다. 바닥 중앙 원점, 미터 단위, 1 표면·1 재질(정점 색), 충돌체 없음. 정확한 수종 모델은 아니다.

| 구성 | 높이·폭 | LOD0 | LOD1 | LOD2 |
|---|---|---:|---:|---:|
| silvergrass_clump | 1.8m · 1.4m | 72 | 13 | 4 |
| silvergrass_patch | 1.9m · 4.0m | 360 | 65 | 4 |
| reed_patch | 2.4m · 3.0m | 288 | 52 | 4 |

수치는 삼각형 수다. LOD 거리 0–40m, 40–150m, 150–900m. LOD2는 512px 교차 카드 2장(알파 컷아웃)이다. 모든 LOD 그림자 없음.
- `*_auto_lod.scn`: 단일 배치용 자동 LOD 씬.
- 대량 배치: `res://scripts/vegetation/vegetation_batch_factory.gd`의 `build("res://assets/generated/silvergrass/%s_lod%d.scn", kind, transforms, lod_ranges, false)`. 4,096개 위치, 16청크, 48 묶음 보존을 확인했다.
- 재생성: `C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe pipeline/processors/silvergrass/generate.py`. 프리뷰 전용 임시 프로젝트에서 생성한다.
