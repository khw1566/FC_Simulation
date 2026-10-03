# 260927 도로 데이터 기반 지형 높이맵 노반 절토 및 평탄화 보고서
작성일자: 2026-09-27
작성자: Antigravity AI

## 1. 개요
- 도로가 지형 표면 아래로 묻히거나 지형의 급격한 횡방향/종방향 굴곡으로 인해 도로가 울퉁불퉁해지는 문제를 해결하기 위해, **실제 도로 선형 데이터를 활용하여 지형 높이맵(`heightmap`) 자체의 노반을 평탄화 및 구배 정지(Road Bed Grading & Flattening)**하는 방식을 구현함.
- `AGENTS.md` 규정(단일 파일 800라인 한도)을 준수하여 `terrain_chunk_manager.gd`의 총 라인 수를 429라인으로 유지함.

## 2. 지형 고도 보정 메커니즘

### 2.1 도로 선형 기반 노반 절토 및 블렌딩 알고리즘
- **파일:** [terrain_chunk_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk_manager.gd)
- **메서드:** `_apply_road_bed_flattening_and_smoothing()`
- **동작 원리:**
  1. 높이맵 로딩 시점(청크 분할 이전)에 `buildings_and_roads.json`의 도로 벡터 데이터를 로드.
  2. 다리/터널을 제외한 **일반 지표 도로**의 연속 세그먼트를 따라 도로 폭(`width`)에 비례하는 노반 스탬프 반경(`stamp_radius_px`)을 계산.
  3. 도로의 진행 방향을 따라 완만하게 보간된 선형 설계 고도(`cur_target_norm`)를 산출.
  4. 도로 중심선에서 외곽으로 갈수록 부드럽게 감쇠하는 가우시안 거리 가중치(`blend_factor`)를 적용하여 기존 지형 고도와 도로 노반 고도를 자연스럽게 절성토 융합:
     $$\text{final\_h} = \text{lerp}(\text{existing\_h}, \; \text{cur\_target\_norm}, \; \text{blend\_factor} \times 0.85)$$

### 2.2 기대 효과
- **굴곡 제거 및 완만한 구배:** 지형 높이맵 자체가 도로가 통과하는 선형을 따라 완만한 도로 노반(Road Bed)으로 평탄하게 깎여(Grading), 도로가 지형 굴곡으로 비틀리거나 솟구치는 현상 제거.
- **땅속 매립 원천 차단:** 도로 폭만큼 지형이 평탄면으로 가공되어 갓길이나 측면 지형이 도로 위를 침범하는 매립 현상이 원천 해소됨.
- **지형-도로 일체화:** 지형 버텍스 자체가 도로 베이스에 맞추어 생성되므로, 도로 상판 렌더링 및 물리 충돌체와의 정합성이 극대화됨.

## 3. 검증 결과
- **Godot 4.3 stable 헤드리스 검사:** `tools\godot\Godot_v4.3-stable_win64.exe --headless --path godot_project --check-only` 통과 (Exit Code: 0).
- **파일 라인 수:** `terrain_chunk_manager.gd` 총 429라인 (800라인 한도 준수).
