# 날짜: 2026-09-26
# 작성자: khw (AI 엔지니어링 어시스턴트)

# 비행 시뮬레이션 고품질·비정형 구름 및 노트북 경량화 그래픽 설정 시스템 구현 완료 보고서

## 1. 개요 및 목적
기존의 인위적인 큐브(BoxMesh AABB) 형태 구름 절단면을 완전히 제거하고, 비행 시뮬레이션에 필수적인 유기적 비정형 외형(Worley-Perlin FBM), 대기 대류(Curl Noise Boiling Effect), 비행체 관통 터널(Wake Cavity)을 구축하는 동시에, 노트북 및 내장 그래픽 환경에서도 60fps로 구동될 수 있도록 초경량 모드와 환경 설정 내 '그래픽' 탭을 신설하였습니다.

---

## 2. 주요 변경 사항 및 기술 구현 사양

### 2.1 셰이더 기반 비정형 유기적 외형 및 큐브 단절 제거 (`volumetric_cloud.gdshader`)
- **Anti-Cube 구면 지수 마스킹:**
  - 셰이더 샘플러 초입에서 중심점 기준 구면 반경 거리($\text{dist}^2 > 0.24$)를 초과하는 외곽을 원천 차단하고 지수 감쇄 곡선($\text{smoothstep}(0.48, 0.20, r)$)을 적용하여 큐브 모서리 절단면 노출을 완전히 제거.
- **Worley(Cellular) + Perlin 하이브리드 FBM 합성:**
  - 뭉게뭉게 피어오르는 응결핵 셀룰러 노이즈와 3옥타브 Value-Perlin 노이즈를 합성하여 현실적인 솜사탕 모양(Billowy Puff) 구현.
- **동적 대류(Boiling Effect):**
  - 시간에 따라 3차원 Curl 노이즈 벡터장을 실시간 중첩하여 구름 내부가 살아서 끓어오르는 대류 모션 부여.
- **비행체 고속 관통 후류 터널 (Wake Cavity):**
  - 플레이어 기체의 로컬 위치 및 속도 벡터에 반응하여 관통 경로 반경 내 구름 밀도를 실시간으로 $0.0$으로 깎아내고 외곽으로 밀어내는 터널링 연산 내장.

### 2.2 사양별 렌더링 품질 분기 및 노트북(Laptop) 최적화
- **4단계 품질 분기 (`quality_mode`):**
  - **0 (울트라):** 28 레이마칭 스텝, 3 광원 스텝, Worley-Perlin + Curl 대류 + 고주파 침식 디테일 + 기체 터널링.
  - **1 (높음 - 기본값):** 16 레이마칭 스텝, 2 광원 스텝, Worley-Perlin + 대류 + 기체 터널링.
  - **2 (보통):** 10 레이마칭 스텝, 1 광원 스텝, Value FBM + 단순 오프셋.
  - **3 (노트북/저사양):** 5 레이마칭 스텝, 광원 루프 생략(정적 앰비언트), Curl 대류 생략, 가시 구름 개수 55% 자동 절감.
  - **4 (구름 끔):** 렌더링 및 프로세스 완전 중단.

### 2.3 환경 설정 UI 그래픽 탭 신설 (`pause_settings_hud.tscn`, `pause_settings_view.gd`, `pause_settings_controller.gd`)
- **모노크롬 탭 바 (TabBar):**
  - `[일반 / 컨트롤]` 탭: 마우스 감도, 비행 벡터 HUD, 기후 On/Off 및 날씨 상태 선택.
  - `[그래픽 / 성능]` 탭: 구름 품질 드롭다운(울트라/높음/보통/노트북/끔), 실시간 그림자, MSAA, 대기 안개.
- **노트북 원클릭 최적화 프리셋 (`BtnLaptopMode`):**
  - 클릭 한 번으로 구름: 노트북/경량 모드, 그림자: OFF, MSAA: OFF, 안개: 유지로 일괄 전환.

---

## 3. 수정 및 생성된 파일 목록

- [volumetric_cloud.gdshader](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/shaders/volumetric_cloud.gdshader)
  - 구면 마스킹, Worley-Perlin 노이즈, 3D Curl 대류, 기체 관통 터널, `quality_mode` 동적 스텝 분기 구현.
- [cloud_cluster_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/weather/cloud_cluster_manager.gd)
  - 플레이어 속도/위치 추적 기반 후류 유니폼 전달, `set_cloud_quality()` 및 노트북 모드 시 활성 구름 수 최적화 구현.
- [weather_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/weather/weather_manager.gd)
  - `set_cloud_quality()` 위임 메서드 추가.
- [pause_settings_hud.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/pause_settings_hud.tscn)
  - 일반/그래픽 탭 구조, 구름 품질 OptionButton, 노트북 최적화 Button 노드 트리 신설.
- [pause_settings_view.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/views/pause_settings_view.gd)
  - 탭 스위칭 로직, 구름 품질 및 노트북 모드 시그널 발행, UI 동기화 구현.
- [pause_settings_controller.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/controllers/pause_settings_controller.gd)
  - 그래픽 옵션 수신 및 렌더러/날씨 매니저 상태 전파 파이프라인 연동.

---

## 4. 검증 결과
- Godot 4.3 stable 헤드리스 씬 및 스크립트 컴파일 문법 검증 결과 오류 없이 정상 통과(Exit Code 0).
