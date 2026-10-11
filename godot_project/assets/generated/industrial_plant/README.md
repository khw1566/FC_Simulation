# 플랜트 탑·배관·연기 에셋
울산 공단의 산업 스카이라인을 표현하기 위한 범용 실루엣이다. 실제 업체·시설 위치·비공개 배치와 설비 사양을 재현하지 않는다. 모든 모델은 1단위=1m, Y축 위쪽, 바닥 Y=0이다.

## 에셋 구성
| 키 | 형태 | 배출 효과 |
|---|---|---|
| stack_concrete | 90m 고층 표식 연통 | 회색 연기 |
| stack_steel | 55m 슬림 강철 연통 | 회색 연기 |
| stack_triple | 62m 3구 집합 연통 | 각 배출구의 회색 연기 |
| flare_lattice | 72m 격자 지지 플레어 탑 | 기본 배출 없음, 불꽃 미구현 |
| process_column | 다단 정유 공정 탑과 보조 배관 | 기본 배출 없음 |
| scrubber_tower | 세정 용기와 38m 배기 연통 | 흰 증기 |
| rack_straight / elbow / tee | 직선·곡관·분기 랙 | 기존 산업 배관과 호환 |
| rack_cross | 같은 높이의 공유 연결 헤더 | 다른 유체의 독립 교차용이 아님 |
| rack_riser | Y=5m에서 9m로 높이 전환 | 연결 모듈의 원점은 항상 Y=0 |
| rack_double | Y=5m·9m의 2층 배관 | 층마다 독립 포트 |

## 플랜트 라인 조립
- 기본 규격은 3열, 관 반경 0.32m, 열 간격 1.1m다. 카탈로그에 각 연결 그룹의 중심과 바깥 방향을 기록했다.
- `PipeConnector0` 등의 Marker3D의 **-Z축이 바깥 방향**이다. 접속할 두 Marker의 위치는 같고 방향은 반대여야 한다.
- 동일한 균일 축척을 사용한다. 같은 포트 규격이라도 서로 다른 축척 또는 비균일 축척은 연결 도우미가 거부한다.
- 24m 직선 랙, 12m 접속 길이, Y=5m·9m 높이를 기준으로 조립한다. 곡관·분기·상하 전환을 조합하고, 유체를 섞지 않을 교차는 서로 다른 층을 사용한다.
- 탑에는 Y=5m의 3열 입력 포트와 집합 헤더가 있다. `process_column` 등은 공정 연출용 고정 외관이며 공정 시뮬레이션이 아니다.
- `plant_assembly_demo.tscn`은 분기, 곡관, 상하 전환과 여러 탑을 조립한 예제다. 일부 탑과 2층 포트는 추가 라인을 붙이도록 열린 상태다. 실제 공단 배치가 아니다.

```gdscript
var helper = preload("res://scripts/industrial_plant/plant_connector.gd")
var connected = helper.snap(
    new_module,
    new_module.get_node("PipeConnector0"),
    previous_module.get_node("PipeConnector1")
)
```

두 모듈을 씬 트리에 추가한 다음 호출한다. 스냅은 배관 포트 기준으로 모듈 전체를 이동·회전하므로 연결 후 점유 범위와 지형 높이를 확인한다.

## 연기와 증기
- 각 모델 씬의 `NightLighting`은 발판 보행등·연통 표식·상향 조명·배관 작업등을 제공한다. 기존 주야간 서비스에 자동 연동하며 자세한 밝기 설정은 `../industrial_lighting/README.md`를 참조한다.
- `smoke_gray.tscn`, `steam_white.tscn`, `smoke_dark.tscn` 세 가지 독립 효과를 제공한다. GLB에는 효과가 없으며 `.tscn`을 사용해야 기본 연기가 함께 나온다.
- 탑의 `SmokeOutlet0/Plume` 등에서 `plume_enabled`, `density`, `wind_velocity`, `buoyancy`를 조절한다. 실행 중 값을 바꾼 다음 `apply_settings()`를 호출한다.
- `wind_velocity`는 풍향과 흐름 강도를 표현하는 연출용 벡터이며 실제 기상 풍속·확산 계산 결과가 아니다. 입자와 가시 범위를 함께 조절한다.
- 각 효과는 최대 96개 GPU 파티클이며 농도로 방출 비율을 조절한다. 많은 탑을 배치할 때 농도를 줄이거나 먼 탑의 효과를 끈다. 자동 거리 LOD는 구현하지 않았다.
- 인스턴스마다 파티클 공정 재질을 복제한다. 서로 다른 탑의 바람 설정이 공유 재질을 변경하지 않는다.
- 외부 비트맵 없이 부드러운 원형 셰이더, 시간에 따른 확대·투명도 변화로 표현한다. 실제 배출물 농도나 유해성을 뜻하지 않는다.
- 기존 냉각탑에도 `steam_white.tscn`을 상단 배출 위치에 자식으로 추가할 수 있다. 원본 냉각탑은 이번 작업에서 변경하지 않았다.

## 수동 갱신
```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/industrial_plant/generate.py
& .venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py
```
독립 확인이 필요할 때만 `pipeline/processors/industrial_plant/verify_preview.py`를 실행한다. 원본 Godot 프로젝트 대신 `previews/industrial_plant_check/project` 복사본에서 임포트·연결·렌더를 확인한다. `preview.png`는 메시 투영이며 연기 렌더는 독립 확인의 `capture.png`에 있다.

GPU 파티클 구성은 [Godot GPUParticles3D](https://docs.godotengine.org/en/4.3/classes/class_gpuparticles3d.html) 및 [ParticleProcessMaterial](https://docs.godotengine.org/en/4.3/classes/class_particleprocessmaterial.html)의 공정 재질·색상·확대 곡선을 사용한다. 충돌·실내·실제 설비 동작과 게임 월드 자동 배치는 포함하지 않았다.

## 커스텀 에셋 경량 표현

외형과 조립 규격을 유지하며 곡면과 반복 장식을 단순화합니다. GLB는 중복 정점을 공유하고 무광 단색 재질을 사용합니다. 기존 조립 씬·연결점·조명·연기 설정과 충돌 형상은 보존합니다.

- 규약: `custom_low_poly_flat_v1`
- 재생성: `.venv_campus/Scripts/python.exe pipeline/processors/custom_lowpoly/build.py`
- 게임·지도·실행 생성기 변경 없음. 원본 프로젝트에서 임포터를 실행하지 않습니다.
- 이전 PNG는 과거 표현일 수 있습니다. 최신 모델은 독립 에셋 프리뷰에서 확인하세요.
