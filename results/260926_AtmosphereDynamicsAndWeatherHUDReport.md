# 날짜: 2026-09-26
# 작성자: khw (AI 엔지니어링 어시스턴트)

# 국제표준대기(ISA) 기반 고도별 기상·대기역학 모델 및 TAB 상세 정보 HUD 구현 완료 보고서

## 1. 개요 및 목적
비행 시뮬레이션 환경에서 향후 정밀 비행 모델(Flight Model, 양력/항력)과 음속·마하수(Mach Number) 계산에 활용될 수 있도록, 실제 항공기상학 및 국제표준대기(ISA) 물리 공식에 기반한 **고도별 기상 및 대기역학 계산 모델(`AtmosphereStateModel`)**을 구축하고, 비행 중 **`TAB` 키**를 눌러 실시간으로 상세 데이터를 열람 및 토글할 수 있는 HUD 시스템을 구현하였습니다.

---

## 2. 물리·대기역학 계산 모델 사양 (`atmosphere_state_model.gd`)

기체의 현재 3차원 위치(고도 $h$) 및 속도($v$), 현재 기본 날씨 상태를 수신하여 다음의 공학적 지표들을 실시간 산출합니다.

### 2.1 열역학 및 대기 상태 방정식
- **고도별 기온 감률 (ISA Troposphere Lapse Rate):**
  - 대류권(해수면~11,000m) 구간에서 100m 상승 시마다 -0.65℃ 감률($L = 0.0065 \text{ K/m}$) 적용.
  - 성층권 하부(11,000m 이상)에서는 극저온 등온층(-56.5℃) 유지.
- **기압 공식 (Barometric Formula):**
  - $P(h) = P_0 \cdot \left(1 - \frac{L \cdot h}{T_0}\right)^{\frac{g \cdot M}{R_0 \cdot L}}$ (표준 해수면 기압 1,013.25 hPa 기준).
- **공기 밀도 (이상기체 상태방정식):**
  - $\rho = \frac{P}{R_{\text{specific}} \cdot T_K}$ ($R_{\text{specific}} = 287.058 \text{ J/(kg}\cdot\text{K)}$).
  - 고도가 높아질수록 공기 밀도가 희박해지는 현상을 정밀하게 모사하여 양력/항력 감소 기반 마련.
- **상대 습도 및 이슬점 감률:**
  - 고도 상승에 따른 수증기압 감쇄 및 구름층(고도 800~2,800m) 통과 시 국소 습도 피크 연출.
  - 마그누스 근사 공식을 통해 이슬점 온도($T_d \approx T - \frac{100 - RH}{5}$) 실시간 계산.

### 2.2 풍속 전단 및 에크만 스파이럴 풍향 모델
- **고도별 풍속 전단(Wind Shear):** 지표 마찰층(0~500m) 탈출 후 고도에 비례하여 풍속이 증가하며, 고고도 제트기류(Jet Stream) 영역에서 강풍 발생.
- **풍향 회전(Veering):** 지구 자전 전향력(코리올리 효과)을 모사하여 고도가 높아질수록 풍향이 시계 방향으로 편향 회전(방위각 0~360° 및 방위 표기).

### 2.3 비행 역학(FM) 및 마하수 연동 지표
- **음속 (Speed of Sound):**
  - $a = \sqrt{\gamma \cdot R \cdot T_K} \approx 20.0468 \cdot \sqrt{T_K}$ (기온에 따라 음속이 변화).
- **마하수 (Mach Number):**
  - $M = \frac{V_{\text{TAS}}}{a}$ (해당 고도의 실시간 음속 기준 정밀 마하수 계산).
- **대기속도 분류 (TAS vs IAS):**
  - 진대기속도(True Airspeed, TAS): 실제 공간 이동 속도.
  - 지시대기속도(Indicated Airspeed, IAS): $V_{\text{IAS}} = V_{\text{TAS}} \cdot \sqrt{\frac{\rho}{\rho_0}}$ (피토관에 가해지는 동압 기반 체감 속도).
- **동압 (Dynamic Pressure):**
  - $q = \frac{1}{2} \rho V^2$ (기체 구조 한계 및 양력/항력 계수 산출의 핵심 변수).

---

## 3. UI 및 HUD 시스템 구현 (`weather_details_hud.tscn`)

- **HUD 토글 조작:** 비행 중 **`TAB` 키**를 누르면 화면 우측 상단에 모노크롬 반투명 카드 형태의 HUD 창이 부드럽게 토글.
- **실시간 10Hz 갱신:** 기체의 고도/속도 변화에 맞춰 매 초 10회 주기로 대기역학 모델을 재계산하여 끊김 없이 최신 지표 표시.
- **표시 지표 레이아웃:**
  - **헤더:** 현재 기상 상태 (맑음/흐림/비/뇌우 등)
  - **고도:** 미터(m) 및 피트(ft) 병기
  - **기온:** 외기 기온(℃) 및 이슬점(℃)
  - **기압/밀도:** hPa 및 kg/m³
  - **습도:** 상대 습도(%)
  - **바람:** 풍속(m/s, Knot) 및 풍향(각도, N/NE/E/SE 등 방위)
  - **FM 공기역학:** 실시간 마하수(Mach), 국소 음속(m/s), TAS/IAS 대기속도(km/h), 동압(Pa)

---

## 4. 생성 및 변경된 파일 목록

- [atmosphere_state_model.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/models/atmosphere_state_model.gd)
  - ISA 표준 대기역학 공식 및 고도별 열역학/풍속/음속/마하수/동압 산출 모델.
- [weather_details_hud_view.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/views/weather_details_hud_view.gd)
  - HUD 시각화 및 라벨 데이터 포맷팅 뷰 클래스.
- [weather_details_hud_controller.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/controllers/weather_details_hud_controller.gd)
  - TAB 키 입력 감지 및 10Hz 대기 모델 계산/동기화 컨트롤러.
- [weather_details_hud.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/weather_details_hud.tscn)
  - 모노크롬 카드 스타일의 HUD 씬.
- [main_world.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/main_world.tscn)
  - CanvasLayer에 WeatherDetailsHUD 인스턴스화 및 컨트롤러 노드 마운트.
- [help_overlay_hud_view.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/views/help_overlay_hud_view.gd)
  - F1 조작 안내문에 TAB 키 토글 가이드 추가.

---

## 5. 검증 결과
- Godot 4.3 stable 헤드리스 씬 컴파일 검사 정상 통과 (오류 0건).
- 비행 중 TAB 키 입력 시 기상 상세 패널이 정상 토글되며, 고도 상승/하강에 따라 기온 하강, 기압/밀도 감쇄, 음속 변화, 마하수 및 동압 연동이 실시간으로 확인 완료.
