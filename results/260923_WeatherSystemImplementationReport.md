날짜: 2026-09-23
작성자: khw (AI 엔지니어링 에이전트)

# 기후 시스템(3D 구름, 강우, 낙뢰) 및 성능 토글 구현 완료 보고서

## 1. 개요 및 목적
본 작업은 광활한 가상 현실 지형 상공에서 사실적인 비행 환경을 제공하기 위해, 형태감을 갖춘 절차적 3D 구름, 기체 속도와 연동되는 강우(비), 실시간 낙뢰 및 천둥 시뮬레이션 시스템을 구축하고, 사용자 성능 최적화를 위해 환경 설정(Pause/Settings HUD)에서 이를 On/Off 할 수 있는 기능을 구현하는 것을 목적으로 합니다.

---

## 2. 구현 컴포넌트 및 세부 명세

### 2.1. 절차적 3D 구름 셰이더 및 클러스터 관리자
- **셰이더 파일:** `godot_project/shaders/procedural_cloud.gdshader`
  - 3D Simplex/Perlin fBM 노이즈 함수를 기반으로 버텍스 법선 방향 정점 변위(`VERTEX += NORMAL * (n - 0.4) * displacement_strength`)를 적용하여 솜사탕과 같은 뚜렷한 3D 덩어리감과 윤곽선을 형성.
  - 상하 고도에 따른 일조 그라데이션(`vertical_shade`)과 시선각 기반 림 라이팅(`rim_strength`)을 결합하여 태양광 투광 효과 표현.
- **클러스터 관리자:** `godot_project/scripts/weather/cloud_cluster_manager.gd`
  - 고도 700m ~ 1400m 상공에 18개의 구름 클러스터를 절차적으로 배치.
  - 각 클러스터는 3~5개의 스케일링된 변형 구체 메시로 조합되어 불규칙한 자연 구름 형태를 띰.
  - 풍속 벡터(`Vector3(8.0, 0.0, 4.0)`)에 따라 월드를 부드럽게 드리프트하며, 플레이어 반경 3500m 이탈 시 바람 반대편으로 자동 순환 리스폰.

### 2.2. 플레이어 추적 동적 강우 시스템
- **제어기 파일:** `godot_project/scripts/weather/rain_particle_controller.gd`
  - 전역 렌더링 부하를 방지하기 위해 플레이어 기체 상단 15m 지점에 고정되는 2,500개의 `GPUParticles3D` 로컬 파티클 에미터 구축.
  - 플레이어의 현재 비행 속도 벡터(`player_node.velocity`)를 실시간 추적하여 기체 진행 방향의 역방향으로 빗줄기 낙하 각도가 동적으로 휘어지도록 물리 연동.

### 2.3. 낙뢰 및 천둥 시뮬레이션 시스템
- **제어기 파일:** `godot_project/scripts/weather/lightning_controller.gd`
  - 6~14초 주기로 플레이어 주변 400m~1800m 영역에 절차적 번개 줄기(`ImmediateMesh`)를 즉각 생성.
  - 번개 타격 순간 `DirectionalLight3D` 태양광 에너지를 6배로 순간 증폭한 뒤 0.18초 내 부드럽게 감쇄시키는 환경광 섬광 구현.
  - 낙뢰 충돌 지점과 기체 간 직선 거리를 측정하여 음속(340m/s)에 비례하는 지연 시간(`actual_dist / 340.0`) 후 천둥 이벤트 계산.

### 2.4. 기후 오케스트레이터 및 성능 온/오프 설정 연동
- **총괄 오케스트레이터:** `godot_project/scripts/weather/weather_manager.gd`
  - `CLEAR`, `CLOUDY`, `RAIN`, `STORM` 상태 머신을 내장하여 날씨에 따른 하늘 안개 밀도, 구름 색상, 강우량, 낙뢰 여부를 통합 제어.
- **설정 메뉴 UI 토글:**
  - `godot_project/scenes/pause_settings_hud.tscn`의 그리드에 `WeatherCheck` 체크박스 추가.
  - `godot_project/scripts/views/pause_settings_view.gd` 및 `pause_settings_controller.gd`에 `weather_toggled(bool)` 신호 및 바인딩 체인 구현.
  - 사용자가 설정을 끄면(`false`) 모든 구름 메시, GPU 파티클, 낙뢰 및 타이머 연산이 즉시 비활성화(`visible = false`, `set_process(false)`)되어 GPU/CPU 부하를 제로화함.
  - `translations.json`에 한국어 및 영어 다국어 라벨 완비.

---

## 3. 검증 결과
- Godot 4.3 엔진 정적 문법 및 씬 의존성 검증(`--headless --check-only`) 수행 결과 파싱 에러 없이 정상 로드 완료.
- 모노크롬 UI 테마 및 파일 크기 800라인 제한, 단일 책임 원칙(SRP) 완벽 준수.
