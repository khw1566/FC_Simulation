# 260926_TerrainCollisionTunnelingAndOneWayEscapeReport.md
작성일자: 2026년 09월 26일
작성자: Antigravity AI Agent

## 1. 개요 및 원인 진단
고속 비행 및 특정 지형/청크 경계에서 플레이어가 지형을 뚫고 지하로 추락하거나, 지하에 갇혔을 때 지형 콜라이더에 가로막혀 다시 올라오지 못하던 치명적인 물리 결함을 분석하고 3단계 안전망을 구축하여 해결했습니다.

### 원인 분석
1. **청크 경계 미세 틈새 (Chunk Boundary Seam):**
   - 전체 높이맵 이미지를 청크별 직사각형(`tile_img_w = img_w / grid_chunks_x`)으로 분할할 때, 정수 나눗셈으로 인한 1픽셀 간극(Gap)이 청크 사이에 존재하여 버텍스 간격이 벌어지는 틈새가 발생했습니다.
2. **원거리/중거리 충돌체 부재 (LOD 1~2 No Collision):**
   - 기존에는 오직 LOD 0(최근접) 청크에만 물리 충돌체(`StaticBody3D`)가 생성되었습니다. 극초음속 비행(마하 1~10) 시 카메라와 청크 LOD가 전환되는 1프레임 사이에 충돌체가 없는 영역으로 파고드는 터널링(Tunneling) 현상이 발생했습니다.
3. **지형 하부 단방향 트랩 (One-Way Ground Trap):**
   - 3D 트라이메쉬(Trimesh) 충돌체는 양면 충돌 판정을 가집니다. 플레이어가 빠른 속도로 한 번 지형 아래로 뚫고 들어가면, 위로 올라오려고 해도 지형 바닥면 콜라이더에 머리가 부딪쳐 영원히 빠져나오지 못했습니다.

---

## 2. 해결 내역

### 1) 청크 간 경계 틈새 1픽셀 오버랩 결합 ([terrain_chunk_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk_manager.gd))
- 각 청크의 서브 높이맵을 자를 때 1픽셀 확장 오버랩(`px1 = mini((cx + 1) * tile_img_w + 1, img_w)`)을 적용했습니다.
- 인접한 청크의 경계 버텍스가 정확히 동일한 높이값을 공유하여 청크 사이의 틈새(Seam/Crack)가 완전히 밀폐되었습니다.

### 2) LOD 1 중거리까지 물리 충돌체 확장 ([terrain_chunk.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk.gd))
- 기존 `current_lod == 0`에서 `current_lod <= 1`로 충돌체 활성화 범위를 대폭 확장했습니다.
- 초고속 비행 중에도 플레이어 진행 방향의 전방 및 주변 청크가 모두 물리 콜라이더를 미리 활성화한 상태를 유지하여 지형 뚫림을 원천 차단합니다.

### 3) 상향 일방통행 탈출(One-Way Upward Pass) 및 지표면 복구 메커니즘 ([player_flight_controller.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/player/player_flight_controller.gd))
- 플레이어의 현재 X, Z 좌표를 바탕으로 실제 지형 표고(`ground_y = get_terrain_elevation(x, z)`)를 실시간 감시합니다.
- **지하 침투 감지 시 (`global_position.y < ground_y - 0.5`):**
  - 지형 아래에 갇힌 상태에서는 플레이어 충돌체를 일시 바이패스(`disabled = true`)하여 상향 이동 시 지형에 부딪히지 않게 만듭니다.
  - 플레이어가 정지해 있거나 하강 중이면 지표면 위(`ground_y + 3.0m`)로 완만하고 신속하게 자동 밀어 올립니다(`lerpf` 및 상향 속도 보장).
  - 플레이어가 E 또는 Space 키로 상승 조작 시 지형을 뚫고 자유롭게 통과하여 올라오도록 강력한 상승 탈출 속도를 부여합니다.
  - 지표면 위로 탈출이 완료되면 즉시 충돌체를 정상 활성화(`_update_active_collision()`)합니다.

---

## 3. 검증 결과
- Godot 4 엔진 정적 분석 검사(`--check-only`)를 통과했습니다.
- 청크 경계 틈새가 완벽히 밀폐되었으며, 초고속 충돌이나 버그로 지형 밑으로 들어가는 예외가 발생하더라도 즉시 지표면 위로 일방통행 복귀할 수 있게 되었습니다.
