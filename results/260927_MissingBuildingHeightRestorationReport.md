# 260927 높이 누락 건물 선별 복원 및 정상 건물 보존 보고서
작성일자: 2026-09-27
작성자: Antigravity AI

## 1. 개요
- 일부 공공 GIS 데이터에서 건물 층수/높이 정보가 누락되어 1층 밑면(바닥 슬래브)만 평면 판자처럼 보이는 건물에 대해, 정상적인 건물의 높이값은 일체 변경하지 않고 **오직 높이가 누락된 건물만 선별(Filtering)하여 복원**하는 작업을 완료함.
- `AGENTS.md` 규정(단일 파일 800라인 한도)을 준수하여 `building_road_manager.gd`의 총 라인 수를 780라인으로 유지함.

## 2. 정밀 선별 및 복원 알고리즘

### 2.1 대상 선별 필터링 조건
- **파일:** [building_road_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd#L224)
- **필터링 조건:** `height <= 4.0m`
  - 정상적인 건물 데이터(기본 2층 이상, 정상 층수 또는 고도 부여 건물)는 조건문을 거치지 않고 **원본 높이를 100% 그대로 유지**.
  - 높이가 누락되어 1층 단층(3.3m~3.8m 내외) 또는 0으로 처리된 비정상 건물만 조건문 내부로 진입.

### 2.2 폴리곤 기하(Span) 분석을 통한 비례 복원
- 높이 누락 건물의 바닥 폴리곤 좌표 범위를 측정하여 가로/세로 최대 스팬(`max_span`)을 산출:
  1. **대형 아파트 동 및 대단지 빌딩 (`max_span >= 30.0m`):**
     - 바닥 길이가 30m가 넘는 판상형/타워형 아파트 동은 15~20층 규모(`clampf(max_span * 0.9, 42.0m, 65.0m)`)로 정상 복원.
  2. **중형 상업/업무 빌딩 (`16.0m <= max_span < 30.0m`):**
     - 4~6층 규모(`clampf(max_span * 0.8, 14.0m, 22.0m)`)로 복원.
  3. **소형 주택/점포 (`max_span < 16.0m`):**
     - 지형 경사면에 묻히지 않도록 최소 2~3층 기본 높이(`8.5m`)를 보장.

### 2.3 박스형 폴백(Fallback) 건물 지원
- 폴리곤이 아닌 박스형 데이터(`size_arr`)에서도 높이(`sy <= 4.0m`)인 결측 빌딩에 대해 동일한 스팬 판정(`maxf(sx, sz) >= 15.0m ? 45.0m : 9.0m`)을 적용.

## 3. 검증 결과
- **Godot 4.3 헤드리스 구문 검사:** `tools\godot\Godot_v4.3-stable_win64.exe --headless --path godot_project --check-only` 통과 (Exit Code: 0).
- **파일 크기:** `godot_project/scripts/terrain/building_road_manager.gd` 총 780라인 (800라인 한도 규정 준수).
