# 경량 대나무 숲 에셋

단일 대나무, 4줄기 군집, 9줄기 숲 타일을 제공한다. 높이 최대 9m, 바닥 중앙 원점, 미터 단위다. 군집은 높이와 잎 방향을 달리하며 숲 타일은 약 8m 간격으로 반복 배치할 수 있다. 정확한 수종·식재 측량 모델은 아니다.

| 구성 | 근경 LOD0 | 중거리 LOD1 | 원경 LOD2 |
|---|---:|---:|---:|
| bamboo_single: 1줄기 | 104 | 24 | 4 |
| bamboo_clump: 4줄기 | 416 | 96 | 4 |
| bamboo_grove: 9줄기 | 936 | 216 | 4 |

수치는 삼각형 수다. 군집 전체를 1개 메시 표면·재질에 병합했다. 줄기는 4면/3면, 근경 마디는 3개, 잎은 단순 양면 삼각형이다. 개별 잎 애니메이션, 물리, 충돌체, 실제 식생 지도 배치는 포함하지 않는다.

- 원경: 512×512 실루엣의 교차 카드 2장, 알파 컷아웃. 반투명 블렌딩을 쓰지 않으며 그림자도 끈다. 위에서 보면 카드 형태가 드러나므로 높은 상공에서의 지면 식생 표현은 별도 선택이 필요하다.
- `*_auto_lod.scn`: 근경 0–70m, 중거리 70–250m, 원경 250–2200m. 전환은 즉시 교체하며 페이드 비용을 사용하지 않는다.
- 대량 배치: `bamboo_batch_factory.gd`의 `build(kind, transforms)` 사용. 64m 청크별 MultiMesh로 묶고 청크 단위 거리 판정. 각 변환에는 지면 높이·회전·크기를 호출자가 지정한다. 지형 높이에 맞춰 뿌리 위치를 제공해야 한다.
- 1만 군집 위치, 64청크, 192 LOD 묶음 및 LOD별 1만 변환 보존을 확인했다. 실제 숲 전체를 GPU로 렌더하여 FPS를 측정한 검사는 아니다. 밀집한 카드의 픽셀 처리량과 3 LOD 버퍼 메모리도 고려해야 한다.

```gdscript
const Bamboo = preload("res://scripts/vegetation/bamboo_batch_factory.gd")
var poses: Array[Transform3D] = []
poses.append(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
add_child(Bamboo.build("bamboo_clump", poses))
```

재생성: `C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe pipeline/processors/bamboo/generate.py`. Pillow와 기존 `tree_geometry.gd`의 공통 삼각형 생성기를 사용한다. 원본 Godot 프로젝트에서 에디터·임포터를 실행하지 않고 프리뷰 전용 임시 프로젝트에서 생성한다. 3종 × 3 LOD 씬 9개, 자동 LOD 씬 3개, 실루엣 PNG 3개를 제공한다.
