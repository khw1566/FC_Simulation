# 범용 공단 에셋
실제 공단의 건물·설비 배치와 무관하게 절차적으로 제작한 게임용 외관 모델이다. 공장·저장·배관·송전·냉각·조선·크레인 총 16종의 독립 GLB와 Godot PackedScene을 제공한다.

| 파일명 | 구성 | 삼각형 수 |
|---|---|---|
| factory_gable | 박공지붕, 측면 창, 하역 출입문 | 548 |
| factory_sawtooth | 톱니지붕, 채광창, 하역 출입문 | 676 |
| factory_flat | 평지붕, 옥상 공조기, 측면 창 | 528 |
| distillation_tower | 원통 탑체, 둥근 상단, 발판·난간, 사다리, 측면 배관 | 6,632 |
| industrial_chimney | 테이퍼 연통, 열린 상단, 표식 띠, 점검 발판·사다리 | 3,516 |
| liquid_storage_tank | 원통형 저장고, 완만한 돔 지붕, 보강 띠, 사다리·연결 배관 | 2,188 |
| lpg_sphere | 구형 저장고, 지지 다리·기초, 사다리·연결 배관 | 1,956 |
| pipeline_straight | 24m 직선 배관 3줄과 지지대 | 240 |
| pipeline_elbow | 90도 곡관 3줄과 지지대 | 1,536 |
| pipeline_tee | 분기 배관 3줄과 지지대 | 432 |
| transmission_tower | 46m 격자 송전탑, 3단 가로대와 애자 | 2,892 |
| cooling_tower | 50m 높이의 열린 냉각탑, 기초와 지지대 | 2,368 |
| cooling_fan_bank | 냉각 팬 6기와 루버 외관 | 1,380 |
| shipbuilding_hangar | 100×180m 외관, 지붕·대형 전면 개구부 | 476 |
| tower_crane | 65m 상단, 주 지브·균형추·운전실·매달린 후크 블록 | 3,312 |
| gantry_crane | 조선용 포털, 상부 트러스·트롤리·인양 블록 | 3,396 |

- 1단위는 1m이며 Y축이 위쪽이다. 모든 모델의 바닥은 Y=0이다.
- 위치 기준은 `GroundOrigin` Marker3D다. 건물은 중심을 기준으로 배치하고 정면 출입부는 +Z 방향이다.
- 전체 모델은 외부 텍스처 없이 GLB 내부 재질을 사용한다.
- `catalog.json`에 씬 경로, 로컬 AABB, 점유 범위, 3m 기본 간격과 권장 축척 범위를 기록했다.
- 무작위 배치에서는 동일한 시드를 사용하면 같은 배치를 재현할 수 있다. 회전·축척 이후 점유 범위를 다시 계산하고 여유 간격을 적용해야 한다.
- 권장 축척 범위는 0.85~1.15다. 배관을 이어 조립하는 경우 연결되는 모듈의 축척과 바닥 높이를 통일한다.
- 배관 연결 그룹 중심은 Y=5m다. `PipeConnector0`부터 순서대로 연결점을 제공하며 각 Marker3D의 -Z축이 접속면의 바깥 방향이다. 위치와 방향은 카탈로그에도 기록했다.
- 실제 공단에 무작위로 배치하는 생성기, 지형 평탄화, 충돌, 내부 공간과 설비 동작은 이번 에셋에 포함하지 않았다.
- 송전탑에는 전선망이 포함되지 않으며 크레인은 고정 포즈다. 격납고는 전면 개구부가 있으나 내부 작업 시설은 없다. 크레인 배치는 기초가 아닌 지브를 포함한 전체 AABB를 사용한다.

## 미리보기
각 `.tscn`에는 시설별 `NightLighting` 리그가 포함된다. 창문·작업등·탑 표식등·설비 상향 조명을 제공하고 기존 주야간 서비스에 자동 연동한다. 자세한 설정은 `../industrial_lighting/README.md`를 참조한다. GLB에는 광원이 없으며 실제 광원은 에셋당 1~4개다.

`preview.png`는 생성 메시를 깊이 버퍼로 투영한 참고 이미지다. 각 칸은 독립 축척이며 Godot 렌더 결과는 아니다.

기존 `previews/asset_browser/AssetPreview.exe`가 실행 중이면 원본 에셋 변경 감지를 통해 목록에 추가된다. 에셋 프리뷰 실행파일은 이번 작업에서 수정하거나 재빌드하지 않았다.

## 재생성
프로젝트 루트에서 프로젝트 가상환경을 사용한다.

```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/industrial/generate.py
& .venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py
```

이름, 권장 축척과 배치 여유는 `config/industrial_assets.json`에 있다. 형태 생성은 `pipeline/processors/industrial/`의 기하·공장·설비·배관 모듈에 분리했다. 생성 시 전용 및 공용 자산 매니페스트와 두 모듈 인덱스를 갱신한다.

## 커스텀 에셋 경량 표현

외형과 조립 규격을 유지하며 곡면과 반복 장식을 단순화합니다. GLB는 중복 정점을 공유하고 무광 단색 재질을 사용합니다. 기존 조립 씬·연결점·조명·연기 설정과 충돌 형상은 보존합니다.

- 규약: `custom_low_poly_flat_v1`
- 재생성: `.venv_campus/Scripts/python.exe pipeline/processors/custom_lowpoly/build.py`
- 게임·지도·실행 생성기 변경 없음. 원본 프로젝트에서 임포터를 실행하지 않습니다.
- 이전 PNG는 과거 표현일 수 있습니다. 최신 모델은 독립 에셋 프리뷰에서 확인하세요.
