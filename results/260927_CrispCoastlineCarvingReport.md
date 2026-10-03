# 260927 정밀 수계 마스크 기반 해안선 고도 단차 조형 및 바다 경계 정상화 보고서
작성일자: 2026-09-27
작성자: Antigravity AI

## 1. 개요
- 첨부된 인게임 스크린샷 분석 결과, 해안선 경계가 불분명하고 바다 영역이 육지 둔덕처럼 허옇고 밋밋하게 노출되던 원인을 규명하고 즉각 수정함.
- 수계 마스크의 해안선 테두리를 기반으로 지형 고도에 명확한 단차(Steep Coastal Edge & Marine Depression)를 부여하고, 지형 셰이더의 하천 물 렌더링이 해양 영역을 침범하던 간섭을 완벽히 차단함.
- `AGENTS.md` 규정(단일 파일 800라인 한도)을 준수함.

## 2. 주요 원인 및 수정 조치

### 2.1 지형 셰이더의 내륙 하천 조건이 해양 해안선을 침범한 문제 수정
- **파일:** [procedural_terrain.gdshader](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/shaders/procedural_terrain.gdshader#L154)
- **원인:** 지형 셰이더에서 `bool is_water = (water_mask > 0.05);`로만 판정하여, 해수면 이하(Y <= 0.0m) 바다 및 해안선 경계부에서도 지형 표면 자체를 물 텍스처로 칠하면서 3D 바다 메쉬와 중복 간섭 및 반투명 얼룩을 유발함.
- **조치:**
  - `bool is_water = (v_world_y > 0.0 && water_mask > 0.35);`로 엄격 제한.
  - 바다(해양) 영역은 독립된 3D 수면 메쉬(`kanmon_water`)가 맑고 깊은 수면을 담당하고, 지형 셰이더는 육지 상류 내륙 하천만 순수하게 담당하도록 분리.

### 2.2 수계 마스크 기반 해안선 고도 3단계 정밀 단차 조형
- **파일:** [terrain_chunk_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk_manager.gd#L275)
- **구현 알고리즘:**
  1. **완전 해양 수역 (`water_mask >= 0.40`):**
     - 지형 표고를 해수면 아래 `-2.5m`로 확실하게 강제 절토 침강시켜 해저 바닥으로 배치. 바다 메쉬 위로 지형이 튀어나오거나 맞물리는 현상 원천 제거.
  2. **해안선 경계/조간대 (`0.15 <= water_mask < 0.40`):**
     - 해수면(`-0.5m ~ -2.0m`)으로 급격히 떨어지는 수직 안벽/호안 경사를 구축하여 해안선 구분이 한눈에 선명하게 드러나도록 조형.
  3. **해안선 직전 육상부 (`0.01 < water_mask < 0.15`):**
     - 항만 부두 및 조선소 육지면이 바닷물에 잠기지 않도록 최소 `+0.8m` 이상의 육지 표고를 보장하여 확실한 방파제/부두 단차를 구현.

## 3. 검증 결과
- **Godot 4.3 헤드리스 검사:** `tools\godot\Godot_v4.3-stable_win64.exe --headless --path godot_project --check-only` 통과 (Exit Code: 0).
- **파일 규격 준수:** `terrain_chunk_manager.gd` 433라인, `procedural_terrain.gdshader` 189라인 (모두 800라인 한도 준수).
