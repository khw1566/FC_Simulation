# 경량 나무 및 원경 에셋

활엽수(broadleaf), 가느다란 수목(slender), 침엽수(conifer), 관목(shrub) 4종. 미터 단위이며 바닥 중앙이 원점이다. 높이는 9m, 11m, 12m, 2.2m. 잎별 메시와 충돌체, 바람 애니메이션은 없다.

| 모델 | 근경 LOD0 | 중거리 LOD1 | 원경 LOD2 |
|---|---:|---:|---:|
| 활엽수 | 128 | 24 | 4 |
| 가느다란 수목 | 92 | 24 | 4 |
| 침엽수 | 72 | 28 | 4 |
| 관목 | 76 | 24 | 4 |

수치는 삼각형 수. 모든 모델은 표면/재질 1개이며 근경·중거리는 정점 색상, 원경은 256×512 투명 컷아웃 카드 2장이다. 원경은 반투명 블렌딩 대신 알파 컷아웃을 사용한다. 가까이에서는 카드 교차와 단순 실루엣이 보일 수 있다.

- 개별 배치: `*_auto_lod.scn`을 사용하면 0–100m 근경, 100–350m 중거리, 350–3000m 원경으로 전환한다. 전환은 즉시 교체되며 페이드 비용을 사용하지 않는다.
- 대량 배치: `res://scripts/vegetation/tree_batch_factory.gd`를 preload하여 `build(kind, transforms)` 사용. 전달 배열은 `Array[Transform3D]`. 회전·크기·지면 높이를 포함한 변환은 호출자가 제공한다.
- 64m 청크별 MultiMesh로 묶어 청크 거리별로 LOD 및 컬링을 적용한다. 청크 내부 모든 나무는 같은 LOD이므로 거리 경계에는 최대 청크 크기 정도의 오차가 있다.
- 그림자는 근경만 사용한다. 각 모델과 LOD의 버퍼는 메모리에 남으므로 3 LOD의 인스턴스 데이터가 필요하다. 밀집 원경 카드의 픽셀 처리량도 고려해야 한다.
- 1만 위치에 대해 64개 청크, 192개 LOD 묶음, LOD별 위치 1만 개 보존을 확인했다. 전체 맵 FPS나 최대 배치 수를 측정한 결과는 아니다.

```gdscript
const Trees = preload("res://scripts/vegetation/tree_batch_factory.gd")
var transforms: Array[Transform3D] = []
transforms.append(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
add_child(Trees.build("broadleaf", transforms))
```

재생성: `C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe pipeline/processors/trees/generate.py`. 기존 .venv_campus는 현재 다른 사용자 경로를 참조하여 실행되지 않으므로 이 작업에서는 설치된 Python 3.12와 Pillow를 사용했다.

전체 맵 배치는 변경하지 않았다. 독립 Godot 4.3 Compatibility에서 모델 생성·렌더 및 대량 배치 구조를 확인했다. 수종별 3 LOD 씬 12개와 자동 LOD 씬 4개를 제공한다.
