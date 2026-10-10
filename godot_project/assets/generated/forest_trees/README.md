# 공통 숲 수목
모든 숲에 같은 품질로 쓰는 경량 수목 12형태다. 수종 4종(활엽 낙엽수, 소나무형, 관목, 대나무) × 형태 3종 × LOD 3단. 바닥 중앙 원점, 미터 단위, 1표면·정점 색 재질, 충돌체 없음. 실제 수종 측량 모델은 아니다.

| 형태 | 높이·폭(m) | LOD0 | LOD1 | LOD2 |
|---|---|---:|---:|---:|
| deciduous_a(꽃병형, 느티나무형) | 12 · 9 | 368 | 68 | 24 |
| deciduous_b(둥근형, 벚나무형) | 8 · 7.5 | 332 | 88 | 24 |
| deciduous_c(타원형) | 14 · 6 | 332 | 88 | 24 |
| pine_a/b/c(기운 줄기·층진 수관) | 11/9/13 · 6~7 | 272 | 76 | 24 |
| shrub_a/b/c | 1.1~2 · 1.6~2.6 | 180 | 60 | 24 |
| bamboo_a/b/c(5~6줄기 군집) | 7.5~10.5 · 2.6~3.6 | 220~264 | 90~96 | 24 |

수치는 삼각형 수다.
- LOD0(0~100m): 잎 덩이 여러 개의 다층 수관, 줄기·주가지. LOD1(100~350m): 덩이를 4개로 묶은 같은 실루엣. LOD2(350~1,500m): 전체를 감싸는 단일 입체 수관(위에서 봐도 둥글다, 카드 아님).
- 정점 색 알파 = 흔들림 가중치(줄기 0, 수관 끝 1). `vegetation_sway.gdshader`의 `use_vertex_weight`로 수관만 흔든다.
- 면은 모두 바깥을 향한다(Godot 시계 방향 앞면).
- 대량 배치: `vegetation_batch_factory.gd`의 `build("res://assets/generated/forest_trees/%s_lod%d.scn", kind, transforms, [[0,100],[100,350],[350,1500]])`. 4,096개 위치, 64청크, 192묶음 보존을 확인했다.
- 재생성: `C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe pipeline/processors/forest_trees/generate.py`. 프리뷰 전용 임시 프로젝트에서 생성한다.
