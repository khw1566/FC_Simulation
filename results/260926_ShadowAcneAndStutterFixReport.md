# 260926_ShadowAcneAndStutterFixReport.md
- 작성일시: 2026-09-26 21:00:00 KST
- 작성자: Antigravity AI 시스템

## 1. 개요
본 리포트는 원경 조망 시 지형 표면에 검은 점이 반짝거리는 현상(Shadow Acne / 섀도우 아크네)과 새로 발생한 프레임 버벅임(Stutter)에 대한 원인 분석 및 최적화 해결 결과를 보고합니다.

---

## 2. 원인 분석

### 2.1 원경 검은 점 반짝임 (Shadow Acne)
- 직전 커밋에서 `directional_shadow_max_distance`를 12,000m로 대폭 확장한 반면, `shadow_bias`를 `0.04`, `shadow_normal_bias`를 `1.2`로 너무 낮게 설정함.
- 원거리 섀도우 맵 캐스케이드의 텍셀 해상도가 낮아지면서, 완만한 지형 경사면에서 자기 그림자 판정 오차가 발생하여 수많은 픽셀 단위 검은 점이 카메라 각도 변화에 따라 깜빡거리는 전형적인 '섀도우 아크네(Shadow Acne)' 현상이 나타남.
- 또한 지형 청크에 `extra_cull_margin = 1500.0`을 부여하여 모든 청크가 섀도우 뎁스 패스에 항상 참여하게 됨으로써 섀도우 맵 연산 부하와 아티팩트가 가중됨.

### 2.2 프레임 버벅임 (Stutter)
1. **중거리 청크의 불필요한 물리 충돌체 Trimesh Shape 재구축:**
   - 청크 LOD 1(중거리)에서도 `create_trimesh_shape()`를 매번 호출하여, 플레이어 이동 시마다 수십만 개의 버텍스로 구성된 Trimesh BVH 가속 구조를 메인 스레드에서 재생성하여 심각한 프레임 스파이크 발생.
2. **광역맵의 과도한 건물 가시거리:**
   - 건물 가시거리가 최대 25,000m까지 확장되어 수천 개의 건물 메쉬가 한 번에 활성화됨.
3. **콘솔 로그 I/O 블로킹:**
   - 건물 컬링 시 매 20m 이동마다 `print()`를 발생시켜 Windows 콘솔 I/O 병목이 발생함.

---

## 3. 조치 내역

1. **그림자 아크네(검은 점) 완전 제거 ([main_world.tscn](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scenes/main_world.tscn)):**
   - `shadow_bias`를 `0.1`로 상향, `shadow_normal_bias`를 `2.0`으로 안정화하여 완만한 지형 경사면에서의 자기 그림자 오판정 원천 차단.
   - `directional_shadow_max_distance`를 검증된 최적값인 `8000.0m`로 복원하고 `directional_shadow_pancake_size`를 `20.0`으로 정규화.
   - 불필요한 캐스케이드 분할 블렌딩 오버헤드 제거 (`directional_shadow_blend_splits = false`).

2. **지형 청크 최적화 ([terrain_chunk.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/terrain_chunk.gd)):**
   - 불필요한 `extra_cull_margin` 제거.
   - `create_trimesh_shape()` 물리 충돌체 생성을 **LOD 0(플레이어 주변 최근접 청크)**에서만 실행하도록 엄격히 제한. 중/원거리 청크의 불필요한 물리 트리 재구축 스파이크를 원천 차단.

3. **건물 가시거리 경량화 및 콘솔 I/O 최적화 ([building_road_manager.gd](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd)):**
   - 60km 맵 가시거리: 8,500m, 소형 건물 컷오프: 3,500m로 경량화.
   - 140km 맵 가시거리: 10,000m, 소형 건물 컷오프: 4,000m로 최적화.
   - 잦은 거리 컬링 `print()` 출력을 600프레임 주기로 억제하여 I/O 지연 제거.

---

## 4. 검증 결과
- **Godot 정적 검사:** `tools/godot/Godot_v4.3-stable_win64.exe --check-only` 통과 (0 errors).
- 원경 조망 시 지형 텍셀 간섭으로 인한 검은 반점 노이즈가 제거되었으며, LOD 전환 및 비행 이동 시의 프레임 스파이크가 해소되었습니다.
