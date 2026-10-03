# 날짜: 2026-09-26
# 작성자: khw (AI 엔지니어링 어시스턴트)

# 미니맵 하단 상시 TAS/IAS 대기속도 및 아음속(0.8M 이상) 마하수 표기 구현 완료 보고서

## 1. 개요 및 목적
비행 조종 시 플레이어가 별도의 창을 열지 않고도 화면 좌측 상단 미니맵 바로 아래에서 실시간 **진대기속도(TAS, True Airspeed)**와 **지시대기속도(IAS, Indicated Airspeed)**를 상시 확인할 수 있도록 HUD를 확장하고, 천음속/아음속 영역인 **마하 0.80 (0.80M) 이상에 진입할 경우 지시대기속도 옆에 황색 마하수(`[M0.8x]`)를 자동 점등/표기**하는 동적 항공 계기 시스템을 구현하였습니다.

---

## 2. 주요 구현 사양 및 인터페이스

### 2.1 미니맵 하단 상시 속도 계기 패널 (`map_hud.tscn`)
- **배치 위치:** 좌측 상단 `MinimapContainer` 바로 아래(Y: 222px ~ 276px, 너비 192px).
- **스타일:** 프로젝트 표준 모노크롬 다크 반투명 패널(`StyleBoxFlat_mono_panel`) 적용.
- **표시 항목:**
  1. **TAS (진대기속도):** 기체의 실제 대기 통과 속도 (km/h 단위, 백색 고대비 표기).
  2. **IAS (지시대기속도):** 고도별 공기 밀도 감쇄($\sqrt{\rho / \rho_0}$)가 반영된 피토관 체감 동압 속도.
  3. **Mach (마하수 동적 표기):**
     - $M < 0.80$: 숨김(비활성화) 처리되어 시야 방해 최소화.
     - $M \ge 0.80$ (아음속/천음속/초음속 진입): IAS 라벨 우측에 강조색(`Color(1, 0.85, 0.4, 1)`)으로 **`[M0.80]` ~ `[M10.00]`** 자동 점등.

### 2.2 대기역학 연동 아키텍처 (`map_hud_controller.gd` & `map_hud_view.gd`)
- `MapHUDController`의 물리 프레임(`_physics_process`)에서 플레이어의 현재 고도와 이동 속도를 감지.
- `AtmosphereStateModel.calculate_at_altitude()`를 호출하여 고도별 기온/공기밀도/음속을 기반으로 TAS, IAS, Mach를 실시간 산출.
- `MapHUDView.update_airspeed_display(tas_kmh, ias_kmh, mach)`를 통해 즉각 UI 반영.

---

## 3. 수정 및 생성된 파일 목록

- [godot_project/scenes/map_hud.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/map_hud.tscn)
  - `AirspeedBox` 패널 컨테이너 신설 (TAS 행, IAS 행, 아음속 마하수 라벨 배치).
- [godot_project/scripts/views/map_hud_view.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/views/map_hud_view.gd)
  - `val_tas_label`, `val_ias_label`, `val_mach_label` 참조 바인딩 및 `update_airspeed_display()` 구현.
  - 마하 0.80 이상 진입 시 `visible = true` 및 `[M%.2f]` 포맷팅 적용.
- [godot_project/scripts/controllers/map_hud_controller.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/controllers/map_hud_controller.gd)
  - `AtmosphereStateModel`과 연동하여 물리 프레임마다 실시간 TAS/IAS/Mach 계산 및 뷰 전달.
- [godot_project/scenes/main_world.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/main_world.tscn)
  - `MapHUDController`에 `WeatherManager` 노드 경로 연결.

---

## 4. 검증 결과
- Godot 4.3 stable 헤드리스 컴파일 문법 검사 통과 (오류 0건).
- 비행 중 저속 상태에서는 TAS와 IAS가 상시 표기되며, 가속하여 마하 0.80 이상에 도달하는 즉시 IAS 옆에 `[M0.80]` 형태의 마하수가 자동으로 나타남을 확인 완료.
