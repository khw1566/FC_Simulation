# [260923] 구름 및 비 이펙트 인게임 렌더링 디버깅 및 복구 리포트
작성일: 2026-09-23
작성자: khw (AI 엔지니어링 어시스턴트)

---

## 1. 개요 및 장애 현상 분석
인게임 실행 시 설정된 구름 볼류메트릭 덩어리와 강우(Rain) 파티클이 전혀 화면에 나타나지 않는 현상을 콘솔 표준 출력과 렌더링 파이프라인 단계별 디버깅 메시지를 삽입하여 추적 및 검증하였습니다.

---

## 2. 근본 원인 (Root Cause) 식별

### 2.1 강우(Rain) 파티클 시스템 로드 실패 (Script Parse Error)
- **원인:** `rain_particle_controller.gd` 내부에서 `BaseMaterial3D.BILLBOARD_PARTICLE_BILLBOARD_Y` 상수를 참조하였으나, Godot 4.3 `BaseMaterial3D`에는 해당 열거형 멤버가 존재하지 않아 스크립트 파싱 오류(`Parse error`)가 발생하였습니다.
- **결과:** 스크립트 로드 자체가 거부되어 `RainParticleController` 노드가 생성 및 렌더링되지 않았습니다.
- **해결:** Godot 4.3 런타임 검증 스크립트 실행을 통해 `BaseMaterial3D.BILLBOARD_PARTICLES` (값: 3) 상수를 확인하고 전면 교체 적용하였습니다.

### 2.2 구름(Volumetric Cloud) 셰이더 좌표계 및 스케일 불일치
- **원인 1:** `BoxMesh`에 가변 크기 `Vector3(var_w, var_h, var_d)`를 직접 할당하면서, 정점 좌표 `VERTEX`가 `[-0.5, 0.5]`가 아닌 수백~수천 미터 단위(`[-1200, 1200]`)로 팽창했습니다. 반면 `volumetric_cloud.gdshader`의 레이마칭 AABB 판정 및 밀도 샘플러는 `[-0.5, 0.5]` 정규화 박스 공간을 전제로 설계되어 광선 교점 판정이 즉시 `discard`되었습니다.
- **원인 2:** 셰이더 내 레이 방향 벡터가 정점 보간 시 정규화 왜곡을 일으켜 교점 계산 실패를 유발했습니다.
- **원인 3:** 노이즈 스케일 역수 계산 `pos * (1.0 / noise_scale)`이 주파수를 과도하게 팽창시켜 밀도가 0 이하로 떨어져 소멸했습니다.
- **해결:**
  - `BoxMesh.size = Vector3.ONE`으로 지정하고 인스턴스 자체의 `scale`로 월드 체적을 부여하여 메쉬 로컬 좌표계를 완전한 `[-0.5, 0.5]` 정규화 바운딩 박스로 일원화하였습니다.
  - 셰이더의 레이 방향을 `normalize(v_obj_vert_pos - v_obj_cam_pos)`로 정확히 보정하였습니다.
  - 노이즈 주파수를 직관적 스케일링(`pos * noise_scale`)으로 안정화하고 `ALBEDO` 및 `ALPHA` 블렌딩 수치를 최적화하였습니다.

### 2.3 기본 기상 상태와 UI 설정 간 불일치
- **원인:** `PauseSettingsController`의 기본 `_weather_state`가 `1 (CIRRUS_FAIR)`로 하드코딩되어 있던 반면, `WeatherManager`는 `2 (PARTLY_CLOUDY)`를 시작 상태로 취하고 있었습니다.
- **해결:** `_weather_state = 2`로 일치시키고, 날씨 전환 드롭다운 변경 시 즉시 7가지 날씨 프리셋과 구름 그룹 가시성이 동기화되도록 연동을 검증하였습니다.

---

## 3. 디버깅 로그 기반 실시간 검증 결과
Godot 4.3 콘솔 환경에서 직접 씬을 구동하여 다음 단계별 정상 가동 로그를 확인 완료하였습니다.

```
[CloudClusterManager] Generated all presets: Cumulus(10), Strato(8), Cirrus(8), CB(4)
[RainParticleController] Initialized Rain Particle System (local_coords=false).
[WeatherManager] apply_weather called with type: 2 (enabled=true)
[CloudClusterManager] configure_composition: Cumulus=0.70, Strato=0.20, Cirrus=0.40, CB=0.00
[CloudClusterManager] Applied group 'Cumulus': 7/10 visible (ratio=0.70)
[CloudClusterManager] Applied group 'Stratocumulus': 2/8 visible (ratio=0.20)
[CloudClusterManager] Applied group 'Cirrus': 3/8 visible (ratio=0.40)
[CloudClusterManager] Applied group 'Cumulonimbus': 0/4 visible (ratio=0.00)
[RainParticleController] Set rain intensity: 0.00 (emitting=false, visible=false)
```

- 적운 7개, 층적운 2개, 권운 3개가 활성화되어 정규화된 3차원 볼륨 박스 내에서 레이마칭으로 안정적으로 렌더링됩니다.
- ESC 일시정지 환경설정에서 날씨를 '비(Rain)' 또는 '뇌우(Storm)'로 변경 시 `RainParticleController`가 `emitting=true`, 강도 0.75~1.0으로 즉시 전환되어 기체 주변에 빗줄기가 정상 흩뿌려집니다.
