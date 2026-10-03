# 260927 방파제/등대 자동 감지 및 3D 렌더링 보고서
작성일자: 2026-09-27
작성자: Antigravity AI

## 1. 개요
- 해안선 수계마스크 중 좁고 긴 선형 구조물을 방파제(Breakwater)로 인식
- 방파제 구조물을 콘크리트 3D 메시로 렌더링하고, 끝단에 등대(Lighthouse)를 배치

## 2. 방파제 감지 기준

| 감지 조건 | 판정 |
|-----------|------|
| `man_made=breakwater/pier/groyne/jetty` 태그 | 무조건 방파제 |
| `natural=coastline` + 종횡비 >= 2.0 + 폭 < 80m + 길이 > 30m | 자동 감지 방파제 |

## 3. 추출 결과

| 맵 | 방파제 수 |
|----|----------|
| 간몬해협 (kanmon_straits) | 4개 |
| 울산광역 (ulsan_metro_60km) | 5개 |

## 4. 구현 구조

### 파이프라인 (Python)
- `pipeline/processors/breakwater_processor.py` (신규)
  - OSM 수계 JSON에서 방파제 폴리라인 추출
  - 폐곡선 폴리곤의 장축 중심선(스켈레톤) 자동 산출
  - `buildings_and_roads.json`에 `breakwaters` 배열로 병합

### Godot 렌더러
- `godot_project/scripts/terrain/breakwater_lighthouse_renderer.gd` (신규, 209행)
  - 방파제: 콘크리트 색상 사다리꼴 단면 구조물 (상면 보도 + 양측면 + 해저 방향 하부 스커트)
  - 등대: 8각 원추형 기둥(12m) + 빨간색 랜턴실(3m) + 원추 지붕 + OmniLight3D 발광체
- `godot_project/scripts/terrain/building_road_manager.gd` (수정)
  - `_render_breakwaters()` 위임 함수 추가 (별도 노드 인스턴스화)

### 방파제 3D 구조물 사양
- 벽체 높이: 4.5m (해수면 위)
- 하부 스커트: 3.0m (해저 방향)
- 폭: 데이터 기반 (최소 5m, 최대 24m)
- 시종점 수직 마감벽 포함

### 등대 3D 구조물 사양
- 기둥: 하부 반경 2.2m, 상부 반경 1.6m, 높이 12m (8각 프리즘)
- 랜턴실: 반경 2.0m, 높이 3m (빨간색 발광)
- 원추 지붕: 높이 2m
- OmniLight3D: 200m 범위, 에너지 5.0

## 5. 검증
- Godot `--check-only`: Exit Code 0 통과
- `building_road_manager.gd`: 800행 한도 내
- `breakwater_lighthouse_renderer.gd`: 209행
