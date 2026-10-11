# 공원·정원 공용 에셋 첫 묶음 제작 결과
기획서의 첫 12개 계열 중 신규 7개 계열(바닥 포함)을 제작하고, 기존 5개 계열을 참조하는 조립 예제를 만들었다. 태화강 국가정원을 비롯한 공원에 반복 사용할 범용 저다각형 에셋이며, 실제 품종·현장 배치의 재현 모델은 아니다.

## 산출물
- 신규 모델 16종, LOD 표현 46개 GLB. GLB와 표현 파일을 에셋 종류 수로 중복 계산하지 않는다.
- 바닥 재질 5종: 잔디, 초지, 흙, 자갈, 대숲 낙엽색 지표. 절차 색상 변화이며 실제 지도와 연결하지 않았다.
- 독립 조립 씬 5개: 잔디 광장, 꽃길, 자연형 화단, 대숲 가장자리, 그늘 쉼터.
- 기존 관목·활엽수·대나무·보행로·벤치를 읽기 전용으로 재사용했다. 동시 생성된 억새·갈대 및 둔치 생태 구역 자산은 변경하지 않았다.
- 출력: godot_project/assets/generated/park_vegetation. 생성기: pipeline/processors/park_vegetation.

## 모델별 제원
삼각형 수와 거리 끝값은 LOD0 / LOD1 / LOD2 순서다. 짧은 풀은 2단계이며 이후 소거한다.

| 모델 | ID | 삼각형 수 | 거리 끝값(m) |
|---|---|---|---|
| 성긴 짧은 풀 | grass_sparse | 48 / 16 | 20 / 60 |
| 조밀한 짧은 풀 | grass_dense | 80 / 24 | 20 / 60 |
| 낮은 꽃무리 | flower_low_round | 168 / 72 / 16 | 35 / 100 / 250 |
| 꽃길 가장자리 군락 | flower_low_edge | 168 / 72 / 16 | 35 / 100 / 250 |
| 직립 초화 군락 | perennial_upright | 140 / 48 / 8 | 40 / 120 / 350 |
| 마른 꽃대 군락 | perennial_dry | 140 / 48 / 8 | 40 / 120 / 350 |
| 가는 잎 관상용 풀 | ornamental_fine | 80 / 32 / 12 | 40 / 120 / 350 |
| 이삭형 관상용 풀 | ornamental_seedhead | 120 / 32 / 12 | 40 / 120 / 350 |
| 생울타리 1m | hedge_1m | 60 / 20 / 12 | 60 / 180 / 500 |
| 생울타리 2m | hedge_2m | 60 / 20 / 12 | 60 / 180 / 500 |
| 생울타리 4m | hedge_4m | 60 / 20 / 12 | 60 / 180 / 500 |
| 생울타리 모서리 | hedge_corner | 72 / 32 / 24 | 60 / 180 / 500 |
| 생울타리 끝단 | hedge_end | 60 / 20 / 12 | 60 / 180 / 500 |
| 작은 조경석 | rock_small | 48 / 24 / 8 | 60 / 180 / 400 |
| 중간 조경석 | rock_medium | 48 / 24 / 8 | 60 / 180 / 400 |
| 조경석 군락 | rock_cluster | 144 / 72 / 8 | 60 / 180 / 400 |

- 전체 전용 출력 69파일, 440,024바이트. 생성 매니페스트·카탈로그·지원 코드 포함.
- 조경석 군락은 근경·중경에서 3개 바위의 묶음이다. 생울타리 모서리는 두 팔을 포함하므로 단일 직선 모듈보다 삼각형 수가 많다.

## 배치·LOD 정책
- 모델당 불투명 정점색 표면 1개, 텍스처 없음, 그림자 없음, 충돌 없음.
- 32m 청크, 같은 종류·LOD를 MultiMesh로 묶는다. 군락별 원점에서 카메라까지의 거리로 셰이더가 단계를 선택하고, 최종 거리+46m 바깥에서는 청크 자체도 소거한다.
- 단계별 메시가 GPU에 제출될 수 있으며, 소거용 셰이더와 청크는 대량 배치 비용을 완전히 없애지 않는다. 전체 지도 FPS는 측정하지 않았다.
- 인스턴스 색상은 명시적으로 흰색을 지정해 원본 정점색을 보존한다. 바람은 기본 0이며 예제에서만 작은 풀·꽃에 0.04를 적용한다. 0.15m AABB 여유를 둔다.
- 넓은 잔디는 바닥 재질로 표현하고 가까운 일부 구간에만 짧은 풀을 배치한다. 바닥 재질의 색상은 각 .tres에서 바꿀 수 있다.
- 생울타리 접속 위치·방향·단면 규격은 catalog.json의 connection_ports에 기록했다. 실제 지리 bbox·래스터 해상도는 null, 고도는 로컬 Y 범위다.

## 확인한 범위
- Godot 4.3 Compatibility / RTX 4070 SUPER에서 실제 임포트와 46모델의 표면·정점색·인덱스 수·높이 범위 검사 통과.
- 2,048개 배치 위치, 8개 청크, 3개 LOD의 24 MultiMesh 배치 구조 확인. 이것은 전체 지도 성능 측정이 아니다.
- 조립 예제 5개 로드 및 실제 렌더링 캡처 완료. overview.png와 각 예제 PNG를 참조한다.
- 읽은 원본 의존성의 해시를 검사 전후 비교했고 변경이 없었다. source_hashes.json에 기록했다.
- 원본 프로젝트 임포터와 전체 맵은 실행하지 않았다. 독립 검증 프로젝트는 previews/asset_browser/park_vegetation_check다.
- 원본 수목·대나무·시설의 원경 LOD를 조립 예제에 자동 연결하지 않았다. 예제는 소규모 배치 확인용이다.

## 재생성
- 명시적 Python으로 pipeline/processors/park_vegetation/generate.py 실행.
- 격리 확인: 같은 Python으로 pipeline/processors/park_vegetation/check.py 실행.
- 요약 이미지·보고: 같은 Python으로 pipeline/processors/park_vegetation/report.py 실행.
- 새 분류 park_vegetation을 색인 코드·지침에 추가했다. 전용·공통 생성 매니페스트에 해시를 병합했다. 색인 갱신 결과는 아래에 기록한다.

## 에셋 색인 갱신
- 지정 명령 `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py`를 실행했으나 가상환경이 없는 khw 사용자 Python을 참조하여 실패했다.
- 대체 명령 `C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe pipeline/indexer/build_asset_index.py`로 수동 갱신을 완료했다.
- 전체 40,300파일, park_vegetation 69파일, pending 0. 보류 파일 없음.
- godot_project/assets/asset_index.json과 ASSET_INDEX.md를 갱신했으며 게임 실행에는 연결하지 않았다. 삭제한 에셋은 없다.
