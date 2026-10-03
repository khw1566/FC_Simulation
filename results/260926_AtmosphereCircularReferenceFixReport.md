# 260926_AtmosphereCircularReferenceFixReport.md
작성일자: 2026년 09월 26일
작성자: Antigravity AI Agent

## 1. 문제 증상 및 근본 원인
게임 실행 중 특정 맵 진입 시 다음과 같은 컴파일 오류가 재발하며 대기역학 계산 및 미니맵 속도 표시, TAB 상세정보가 멈추던 문제를 해결했습니다.

### 오류 로그
```text
SCRIPT ERROR: Compile Error: Identifier not found: AtmosphereStateModel
          at: GDScript::reload (res://scripts/models/atmosphere_state_model.gd:35)
ERROR: Failed to load script "res://scripts/controllers/map_hud_controller.gd" with error "Compile Error"
SCRIPT ERROR: Invalid call. Nonexistent function 'calculate_at_altitude' in base 'GDScript'.
```

### 근본 원인 (GDScript 자기참조 순환 컴파일 버그)
- `atmosphere_state_model.gd` 스크립트 내부에서 선언된 정적 팩토리 메서드 `calculate_at_altitude`의 반환 타입과 내부 인스턴스화 구문이 자기 자신의 클래스명(`AtmosphereStateModel`)을 직접 참조하고 있었습니다:
  ```gdscript
  # 문제 코드:
  static func calculate_at_altitude(...) -> AtmosphereStateModel:
      var state = AtmosphereStateModel.new() # 컴파일 시점에 아직 클래스 등록이 끝나지 않아 식별자 미발견 에러 발생
  ```
- GDScript 컴파일러가 해당 스크립트를 컴파일하는 동안 전역 클래스명 심볼 테이블에 아직 `AtmosphereStateModel`이 온전히 등록되지 않은 상태에서 본문 내 정적 함수가 자기 자신의 클래스명을 참조하면서 `Identifier not found: AtmosphereStateModel` 컴파일 실패가 발생했습니다.
- 이로 인해 해당 클래스를 preload하거나 참조하는 모든 컨트롤러(`map_hud_controller.gd`, `weather_details_hud_controller.gd`)가 로드에 실패하고 런타임에 속도 및 기상 데이터 갱신이 중단되었습니다.

---

## 2. 해결 내역
- [atmosphere_state_model.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/models/atmosphere_state_model.gd)의 자기 참조 구문을 프로젝트 표준 패턴(`map_config_model.gd` 방식)으로 변경했습니다:
  ```gdscript
  ## ISA 기반 특정 고도에서의 대기 상태 계산기
  static func calculate_at_altitude(alt_m: float, ground_speed_ms: float, base_weather_type: int = 2) -> RefCounted:
      var state = load("res://scripts/models/atmosphere_state_model.gd").new()
      state.altitude_m = alt_m
      ...
      return state
  ```
- 정적 분석 및 런타임 컴파일 시 자기참조 심볼 충돌 없이 안전하게 인스턴스가 생성되고 반환됩니다.

---

## 3. 검증 결과
- Godot 4 엔진 구문 검사(`check-only`) 완벽 통과.
- 실제 Godot 프로세스 기동 테스트에서 Vulkan 디바이스 초기화 및 7개 맵 로드 과정에서 컴파일 에러가 일체 발생하지 않음을 검증했습니다.
- 이제 미니맵 하단 실시간 TAS / IAS 및 마하수 계산, TAB 키 기상 상세정보 뷰가 정상적으로 갱신됩니다.
