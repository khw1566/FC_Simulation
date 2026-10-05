# 범용 철로 터널 에셋
고속철도용과 동해선용 복선 터널을 각각 입구·반복 내부 구간·출구·연결 세트로 제공한다. 정적 Godot PackedScene이며 외부 텍스처나 실행 스크립트 의존성이 없다. 내부 구조 확인용 씬 2개는 별도로 제공한다.

| 형식 | 고속철도용 hsr | 동해선용 donghae |
|---|---|---|
| 궤도 | 슬래브 | 자갈 도상 |
| 기준 내부 폭 | 13.6m | 11.6m |
| 바닥 기준 천장 Y | 9m | 8m |
| 선간 중심 거리 | 5.4m | 4.4m |
| 입구/출구 길이 | 각각 8m | 각각 6m |
| 반복 내부 구간 길이 | 24m | 20m |
| 조립 완료 길이 | 64m | 52m |
| 조립 완료 삼각형 수 | 8,904 | 12,216 |

## 파일 구성
- `hsr_tunnel_entry.scn`, `donghae_tunnel_entry.scn`: 입구. 고속철도용은 넓게 확장된 갱구, 동해선용은 상대적으로 작은 확폭과 콘크리트 외측 벽을 사용한다.
- `hsr_tunnel_body.scn`, `donghae_tunnel_body.scn`: 반복해서 이어 붙이는 내부 구간.
- `hsr_tunnel_exit.scn`, `donghae_tunnel_exit.scn`: +Z 끝쪽이 확장된 출구. 입구 모델을 뒤집지 않고 연결 방향을 유지한다.
- `hsr_tunnel_set.scn`, `donghae_tunnel_set.scn`: 입구 → 내부 2개 → 출구의 조립 완료 씬.
- `hsr_tunnel_inspection.scn`, `donghae_tunnel_inspection.scn`: 라이닝을 숨기고 물리 충돌을 비활성화한 내부 구조 확인용 씬. 게임 배치에는 사용하지 않는다.

## 연결과 배치
- 1 단위는 1m이며 +Z로 진행한다. 루트 Y=0은 궤도 바닥 기준이다. 레일 상면은 Y=0.12m다.
- TrackStart/TrackEnd는 중앙 연결점이다. Track0Start/Track0End, Track1Start/Track1End는 각 선로 중심 연결점이다.
- 이전 모듈의 끝 Z좌표에 다음 모듈의 원점을 배치한다. 같은 형식끼리 연결하면 라이닝 접속 단면과 양쪽 선로 위치가 일치한다.
- 길이를 늘릴 때 body 모듈을 추가한다. 입구와 출구는 양 끝에만 배치한다.
- 궤간은 모두 1.435m이며 기존 철로·교량과 연결하려면 선간 중심 거리도 같은 값으로 맞춘다. 현재 안양교 세트의 5.4m 선간 거리에는 고속철도용 터널이 대응한다.
- 벽·천장·바닥·보행로·도상에 충돌을 제공한다. 갱구는 중공이며 가운데를 막는 캡이 없다.
- 양측 보행로, 배수로, 케이블 트레이, 가선과 천장 지지 부재, 표시등·조명 부재를 포함한다.
- 조명에는 발광 재질, 원거리 식별 표시와 거리 페이드가 적용된 실제 광원을 포함한다. 열차 운행 경로, 음향, 환기 및 지형 굴착은 별도로 연결한다.
- 기존 게임 씬과 지도 철도 네트워크에는 배치하거나 연결하지 않았다. 터널 내부 지형 제거·입구 지형 맞춤은 배치 단계에서 수행한다.

## 프리뷰
`previews/asset_browser/AssetPreview.exe`를 사용한다. 실행 중 안정된 자산을 자동으로 감지하므로 실행기를 재빌드할 필요가 없다. `railway_tunnels`, `hsr_tunnel`, `donghae_tunnel`로 검색하면 모델과 내부 구조 확인용 씬을 찾을 수 있다. 프리뷰의 파일 표시 이름은 설치된 브라우저의 카탈로그 규칙을 따른다.

실제 렌더 이미지와 비교 시트는 `previews/asset_browser/railway_tunnel_capture/images/`에 저장한다. 원본 게임 프로젝트에서 에디터나 임포터를 실행하지 않는다.

## 재생성
`config/railway_tunnel_assets.json`에서 폭, 높이, 궤도 간격, 입구 확폭, 모듈 길이, 반복 수 등을 변경할 수 있다.

```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/build_railway_tunnel_assets.py
# 프리뷰 전용 렌더 이미지도 갱신
& .venv_campus/Scripts/python.exe pipeline/processors/build_railway_tunnel_assets.py --capture-previews
```

생성기는 프리뷰 전용 경로의 고유 임시 프로젝트를 사용하며 실행 중인 전체 에셋 프리뷰 캐시와 공유하지 않는다. 완성된 자산은 원자적 파일 교체로 공개한다. 개별 및 공용 매니페스트에 해시, 로컬 AABB, 고도 범위와 모델 제원을 기록한다. 지리 좌표와 래스터 해상도는 해당하지 않아 bbox 및 resolution을 null로 기록했다.

특정 실물이나 철도 설계 기준을 복제한 모델이 아니다. 단면·확폭·가선 및 보행 설비의 치수는 게임용 제작 설정값이다. 궤도 형식은 기존 프로젝트의 고속철도 slab, 동해선 ballast 설정을 따른다.
