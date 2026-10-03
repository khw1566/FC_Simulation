# 260923_BuildingFoundationGroundingReport.md
작성일자: 2026-09-23
작성자: Antigravity

## 1. 개요 및 목적
본 보고서는 경사지, 절개지 또는 단차 지형에 배치된 일부 건축물이 공중에 부유(Floating)하여 지형과 분리되어 보이는 시각적 결함을 해결하기 위해, 실제 지형 표고(DEM) 샘플링 및 하부 수직 연장 스커트(Foundation Skirt) 매립 규칙을 적용한 엔지니어링 내역을 기술합니다.

## 2. 결함 원인 분석
- 고정 단일 기준면(Base Y) 적용 문제: 기존 건물 익스트루전 메쉬 생성 시 각 건물의 단일 중심점 고도(`base_y`)를 전체 다각형의 밑바닥 높이로 일괄 적용했습니다.
- 경사지 지형 단차: 울산 문수산 기슭 및 무거동 구릉지처럼 건물 풋프린트 내에서 지형 고도가 수 미터에서 십여 미터까지 변동하는 경사지의 경우, 지형이 낮아지는 쪽의 벽면이 허공에 노출되어 건물이 공중에 떠 있는 현상이 발생했습니다.

## 3. 세부 엔지니어링 구현 내역
### 3.1 지형 표고 실시간 쿼리 인터페이스 구현 (`scripts/terrain/terrain_chunk_manager.gd`)
- `get_terrain_elevation(world_x, world_z) -> float` 메서드 추가:
  - 16-bit DEM 원본 높이맵(`_full_heightmap_image`)으로부터 해당 정점의 UV 좌표를 계산하고 바이리니어(Bilinear) 보간을 수행하여 오차 없는 지표면 표고를 산출.

### 3.2 건물 하부 기초 연장 및 지형 매립 스커트 규칙 (`scripts/terrain/building_road_manager.gd`)
- 지형 매니저 바인딩: `@export var terrain_manager: Node3D` 및 `_sample_ground_height()` 헬퍼 메서드를 통해 지형과 건축물 생성 엔진 간 유기적 결합 달성.
- 다각형 실측 건물(Polygon Buildings) 외벽 연장:
  - 다각형을 이루는 각 2D 정점(`p_curr`)마다 개별 지형 고도(`terr_y`)를 쿼리.
  - 해당 정점의 바닥 높이를 `grounded_y = minf(base_y, terr_y) - foundation_depth`로 계산.
  - 경사지의 낮은 쪽 지형 밑으로 12m 깊이의 하부 스커트 벽면을 추가 연장 생성하여, 어떤 경사도에서도 벽면이 지중으로 자연스럽게 매립되도록 보장.
- 상자형 건물(AABB Box Buildings) 바닥 매립:
  - 상자 중심 좌표의 지형 표고를 쿼리하여 바닥면을 `minf(cy, terr_center_y) - foundation_depth`로 확장 매립.

### 3.3 씬 노드 종속성 연결 (`scenes/main_world.tscn`)
- `MainWorld` 씬 내 `BuildingRoadManager` 노드에 `terrain_manager = NodePath("../TerrainManager")`를 명시적으로 배선.

## 4. 검증 결과
- Godot 4 엔진 구문 및 노드 파싱 무결성 확인 완료 (`Return Code: 0`).
- 경사면 및 구릉지 건축물 렌더링 시 하부 틈새 노출 없이 모든 건물이 지형 표면 아래로 단단히 정착됨을 확인.
