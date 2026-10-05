# 공단 야간 조명
기존 공단 16종과 플랜트 탑·배관 12종의 `.tscn`에 시설별 야간 조명 리그를 부착한다. 원본 GLB, 배관 연결점과 연기 효과는 유지한다.

## 조명 구성
- 공장·격납고: 일부 창의 따뜻한 발광, 차가운 외벽등, 출입부 작업등.
- 저장고·냉각설비: 둘레등과 하부 조명으로 곡면을 드러낸다.
- 탑: 발판 보행등, 하부 상향 조명, 작은 적색 상단 표식.
- 크레인: 지브·교량부 작업등과 하향 조명.
- 배관: 지지대 작업등과 연결부의 국소 조명.
- 장식 발광과 작은 부드러운 후광은 다수 사용하고 실제 광원은 에셋당 1~4개로 제한한다. 실제 광원은 그림자를 끄고 카메라 350~550m 사이에서 소거한다. 장식 발광은 멀리서도 남는다.

## 사용 및 주야간 전환
기존 `.tscn`을 그대로 사용하면 `NightLighting` 자식에 조명이 포함된다. GLB만 직접 로드하면 조명이 포함되지 않는다.

`NightLighting`은 같은 씬의 `DayNightCycleService`를 찾아 신호를 구독한다. `CelestialBodyManager`가 있으면 태양의 실제 방향을 읽고, 없으면 시간대에 따라 황혼부터 점등한다. 서비스를 수정하거나 새 게임 월드를 만들지 않는다. 주야간 서비스가 없는 독립 에셋은 기본 점등한다.

```gdscript
var rig = asset.get_node("NightLighting")
rig.set_night_factor(1.0) # 자동 시간을 해제하고 야간 고정
rig.brightness = 0.7
rig.local_lights_enabled = true
rig.apply_settings()
```

`set_night_factor(0.0)`으로 소등한다. 자동 전환을 다시 사용하려면 `automatic_time=true`를 설정하고 `apply_settings()`를 호출한다. 대량 배치 시 `local_lights_enabled=false`로 실제 광원만 끄고 발광 외관을 유지할 수 있다. 각 인스턴스의 재질·광량은 독립이다.

전체 지도에서 동시에 보이는 광원 수와 성능은 확인하지 않았다. Compatibility 렌더러는 기본적으로 메시 하나당 OmniLight3D 8개 제한이 있으므로 밀집 배치에서는 발광만 사용하거나 광원 범위를 조절한다. [Godot 4.3 OmniLight3D](https://docs.godotengine.org/en/4.3/classes/class_omnilight3d.html)

## 수동 갱신
```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/industrial_lighting/apply.py
& .venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py
```
두 공단 생성기에도 부착 단계를 연결했으므로 모델을 다시 생성해도 조명이 유지된다. 독립 야경 확인은 `pipeline/processors/industrial_lighting/preview.py`로 수행하며 결과는 `previews/industrial_night/night.png`에 기록한다. 원본 프로젝트의 임포터와 전체 지도는 실행하지 않는다.
