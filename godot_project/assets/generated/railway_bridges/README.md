# 철도 교량 에셋
범용 교량 5종과 안양교–울산역 연결 세트를 구성하는 4개 모듈, 조립 완료 씬 1개를 제공한다. 모두 정적 Godot PackedScene이며 월드 데이터나 생성 스크립트 없이 인스턴스화할 수 있다.

| 씬 파일 | 종류 | 길이(m) | 궤도 | 삼각형 |
|---|---|---|---|---|
| rail_box_girder.scn | 콘크리트 박스거더 | 32 | 복선 | 1,440 |
| rail_plate_girder.scn | 강판거더 | 24 | 단선 | 1,164 |
| rail_through_truss.scn | 강재 트러스 | 72 | 복선 | 3,492 |
| rail_deck_arch.scn | 상로 아치 | 120 | 복선 | 5,904 |
| rail_multi_viaduct.scn | 다경간 고가교 | 160 | 복선 | 6,144 |
| anyang_north_approach.scn | 안양교 북측 접근부 | 235 | 복선 | 8,988 |
| anyang_main_bridge.scn | 안양교 병렬 아치 본체 | 231.8 | 복선 | 19,572 |
| anyang_station_approach.scn | 울산역 방향 접근부 | 320 | 복선 | 12,012 |
| ulsan_station_interface.scn | 울산역 궤도 연결부 | 48 | 복선 | 1,620 |
| ulsan_anyang_connected_set.scn | 위 4개 모듈의 연속 조립 씬 | 834.8 | 복선 | 42,012 |

## 안양교 연결 세트
`ulsan_anyang_connected_set.scn` 하나를 인스턴스화하면 북측 접근부 → 안양교 → 울산역 방향 접근부 → 역 연결부 순서로 연결된 모델을 표시한다. 내부 모듈을 분리해서 재사용할 수도 있다. 역 연결부는 기존 역 에셋을 붙이기 위한 짧은 궤도 구간과 외측 플랫폼 가장자리이며 울산역 전체 건물·승강장·분기기 복원 모델은 아니다.

| 모듈 | 시작 Z(m) | 종료 Z(m) |
|---|---|---|
| 북측 접근부 | 0 | 235 |
| 안양교 본체 | 235 | 466.8 |
| 울산역 방향 접근부 | 466.8 | 786.8 |
| 역 연결부 | 786.8 | 834.8 |

접속부 3곳의 양쪽 궤도 연결점 위치가 일치하며 궤간, 선간 거리, 레일 높이가 연속이다. 연결점의 오차는 생성 시 0.1mm 이내로 검사한다. 연결 세트 내부에서는 경계의 끝 교각을 다음 모듈이 담당하여 중복을 줄인다. 단독 모듈은 양 끝 교각을 포함한다.

## 좌표 및 궤도 규약
- 1 단위는 1m다. 루트 원점은 시작 단면 중앙의 궤도 바닥 Y=0이다. +Z 방향으로 교량이 진행한다.
- 레일 상면은 Y=0.12m다. 기존 RailwayTrackBuilder의 레일 기준 높이와 맞춘 게임용 규약이다. 레일 위치의 좌우 간격은 1.435m다.
- 범용 복선의 선간 중심 거리는 5m, 안양교 세트는 5.4m다. 서로 연결할 때 같은 값으로 재생성한다. 단선과 복선을 접속하려면 별도 전환·분기 선형이 필요하다.
- TrackStart/TrackEnd는 중앙 기준점이다. Track0Start/Track0End 및 Track1Start/Track1End는 각 선로 중심 기준점이다. 조립 씬의 개별 궤도 기준점은 각 모듈 아래에 있다.
- 조립 씬의 UlsanStationSocket은 Z=834.8m, Y=0.12m에 있다. 외부 역의 궤도 시작점과 이 점을 맞춘다.
- 교각과 기초는 루트 아래로 생성된다. 원점을 실제 궤도 바닥 높이에 배치하고 pier_height_m을 지형에 맞춰 재생성한다. 실제 지형을 자동으로 읽거나 교각 높이를 추정하지 않는다.
- 상판 충돌을 포함한다. 열차 운행은 별도 철도 경로 시스템이 담당한다. 시각 에셋의 레일과 가선은 운행 경로를 자동 생성하지 않는다.
- 월드 배치는 하지 않았다. 기존 RailwayWorldManager나 철도 네트워크는 변경하지 않았다.

## 실행 및 재생성
`previews/preview_railway_bridges.bat`를 더블클릭한다. 상단 목록으로 10개 모델을 선택한다. 드래그 회전, 휠 확대, Shift+드래그 이동, R 초기화, Esc 종료를 지원한다. 대형 맵을 읽지 않는다.

`config/railway_bridge_assets.json`에서 길이, 폭, 교각 높이, 궤간, 선간 거리와 가선 간격을 변경할 수 있다.

```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/build_railway_bridge_assets.py
# 실제 렌더 이미지와 비교 시트까지 갱신
& .venv_campus/Scripts/python.exe pipeline/processors/build_railway_bridge_assets.py --capture-previews
```

재생성은 임시 경량 프로젝트에서 이루어지며 개별 및 공용 자산 매니페스트와 모듈 인덱스를 갱신한다. 로컬 AABB, 고도 범위, 해시, 삼각형 수, 연결 규약과 정확도 설명을 기록한다. 지리 좌표 배치가 없으므로 bbox와 resolution은 null이다.

## 정확도와 출처
안양교는 울산역 북측의 언양 고가 아치부를 기준으로 한다. [UNIST·한국철도기술연구원 연구 논문](https://pmc.ncbi.nlm.nih.gov/articles/PMC5981442/)의 총길이 231.8m, 중앙 경간 70.4m, 높이 10m, 상하행 병렬 교량과 주아치 위 소아치 특징을 반영했다. [한국철도학회 연구](https://www.kci.go.kr/kciportal/ci/sereArticleSearch/ciSereArtiView.kci?sereArticleSearchBean.artiId=ART002322862)와 [프로젝트 철도 원본의 지도 선형](https://www.openstreetmap.org/way/128255609)을 참고했다.

주아치 양쪽 길이 배분, 리브 위치, 교각 및 상세 부재, 접근부의 길이·높이·직선 방향, 역 접속부는 제작 가정이다. 접근부 합계와 아치부를 합친 786.8m 구성은 실제 접근부 구간별 측량값을 의미하지 않는다. 게임용 근사 모델이며 실제 지도상의 울산역까지의 위치와 전체 역 구내 선형을 재현하지 않는다. 범용 교량은 특정 실물이나 구조 설계 기준에 대한 복제품이 아니다.

## 야간 식별

양측 반복 식별 표시와 근거리 실제 광원을 포함한다. 공유 설정은 `../railway/night_lighting.json`이며 표시등은 낮에도 유지한다. 실제 광원은 그림자 없이 거리 페이드로 제한한다.

## 철로·교량 경량 표현

단색 재질과 성긴 반복 부재를 사용합니다. 접속점, 광원과 기존 충돌 형상은 보존합니다. 계단과 징검다리의 보행판도 보존합니다. 외부 텍스처는 사용하지 않으며 야간 표시의 내장 그라데이션은 8×8입니다.

- 품질 규약: `rail_bridge_low_poly_v1`
- 재생성: 프로젝트 루트에서 `.venv_campus/Scripts/python.exe pipeline/processors/rail_bridge_lowpoly/build.py`
- 생성은 독립 프리뷰 작업 공간에서만 수행합니다. 게임과 지도에 자동 적용하지 않습니다.
- 기존 PNG 프리뷰는 이전 표현일 수 있습니다. 현재 SCN을 독립 에셋 프리뷰에서 확인하세요.
