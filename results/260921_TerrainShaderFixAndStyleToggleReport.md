# 260921_TerrainShaderFixAndStyleToggleReport.md
작성 일자: 2026-09-21
작성자: Antigravity AI 시스템 엔지니어

## 1. 개요 및 원인 분석
- **발생 오류:** `Shader compilation failed` 및 `Parameter "version" is null`
- **원인 분석:**
  1. `godot_project/shaders/procedural_terrain.gdshader` 내 73번 라인(피복 스플랫맵 샘플링)과 121번 라인(수계 마스크 샘플링)에서 `vec2 world_uv` 로컬 변수가 2회 중복 선언되어 GLSL 셰이더 컴파일 오류가 발생함.
  2. 셰이더 컴파일 실패로 인해 Godot 4 Forward+ 렌더러가 유효한 셰이더 바이너리 버전을 취득하지 못해 지형 메쉬 전체의 텍스처 렌더링이 중단됨.

## 2. 해결 및 구현 내역
### 2.1. 셰이더 중복 변수 제거 및 문법 정상화
- `procedural_terrain.gdshader`의 `fragment()` 진입부에 단일 `world_uv`를 선언하여 스플랫맵 및 수계 마스크 샘플링에서 공용하도록 수정했습니다.

### 2.2. 기존 등고선 심플 모드 토글 기능 구현
- **셰이더 Uniform 추가:**
  - `uniform bool simple_contour_mode = false;` (기본값: false = 위성 지표 피복 정밀 텍스처 렌더링)
  - `uniform vec4 simple_land_color : source_color = vec4(0.82, 0.84, 0.85, 1.0);` (모노크롬 테마 친화적 단색 육지)
  - `uniform vec4 simple_water_color : source_color = vec4(0.20, 0.28, 0.35, 1.0);` (단색 수계)
- **모드 분기:**
  - `simple_contour_mode == true`: 복잡한 스플랫맵 믹싱 대신 단색 지형과 명확한 25m 등고선 선(두께 및 투명도 증강)으로 직관적 지형 형태 렌더링.
  - `simple_contour_mode == false (기본값)`: 4채널 SegFormer 인공위성 지표 피복(산림 녹음, 농경지/논밭 그리드, 도회지 아스팔트, 하천/호수) 및 바이옴 고도 블렌딩 렌더링 정상 출력.

### 2.3. 키보드 단축키 및 HUD 연동
- **단축키 할당:** `[T]` 키 입력 시 지형 렌더링 스타일 실시간 전환 (`위성 피복 [T]` <-> `심플 등고선 [T]`).
- **HUD 연동:** `SpeedHUDView` 상태 표시줄에 현재 활성화된 지형 렌더링 모드를 직관적으로 표기.
- **씬 노드 바인딩:** `main_world.tscn` 내 `Player` 노드에 `TerrainManager` 노드 경로 연결 완료.
