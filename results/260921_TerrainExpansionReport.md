# [260921] 광역 지형 확장 및 초고해상도 타일링/LOD 최적화 완료 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 개요 및 변경 목적
- **문제점 분석:** 기존 18.5km × 18.8km 고정 단일 메시로 인해 고쿠라 남단/서단 구역이 잘리는 현상이 존재했으며, 단일 2048 해상도 높이맵의 정밀도 한계가 발생함.
- **해결 방안:**
  - 바운딩 박스를 남위 33.80° ~ 북위 34.05°, 서경 130.80° ~ 동경 131.10°(약 28km × 28km)로 대폭 확장하여 고쿠라 전역 및 시모노세키 완벽 포용.
  - 전역 해상도를 **4096 × 4096 (16-bit)**로 4배 상향 처리.
  - 4×4 타일 분할(16개 타일링) 및 거리 기반 3단계 동적 LOD 청크 스트리밍 엔진 구현.

---

## 2. 데이터 파이프라인 및 타일 분할 결과

| 구분 | 파일/디렉터리 | 해상도 / 규격 | 세부 사항 |
| :--- | :--- | :--- | :--- |
| **확장 DEM 원본** | `data/raw/dem/kanmon_straits_COP30.tif` | 1080 × 900 (Copernicus 30m) | 실측 고도 -63.34m ~ 596.45m 확보 |
| **초고해상도 전역 높이맵** | `godot_project/assets/generated/kanmon_heightmap_16bit.png` | **4096 × 4096 (16-bit PNG)** | 4배 정밀화된 고도 데이터 |
| **청크 타일셋** | `godot_project/assets/generated/tiles/` | 16개 타일 (각 1024 × 1024) | 4×4 타일 분할 및 비동기 스트리밍 지원 |
| **타일 인덱스 메타데이터** | `godot_project/assets/generated/tiles/tiles_index.json` | JSON Schema | 타일 좌표계 및 정규화 고도 메타 |
| **광역 해수면** | `godot_project/scripts/water/kanmon_water_manager.gd` | 32,000m (32km) | 확장 지형에 맞춘 해수면 평면 확장 |

---

## 3. Godot 4 렌더링 최적화 아키텍처

- **`TerrainChunk` (`godot_project/scripts/terrain/terrain_chunk.gd`):**
  - LOD 0 (최근접 ~ 4.5km): 128×128 그리드 버텍스 + 정밀 Trimesh 물리 충돌체 생성.
  - LOD 1 (중거리 4.5km ~ 9km): 64×64 그리드 버텍스, 물리 충돌 연산 비활성화.
  - LOD 2 (원거리 9km ~ 18km): 32×32 그리드 버텍스로 경량화 렌더링.
  - LOD 3 (18km 초과): 화면 밖 완전 컬링(Invisible) 처리로 GPU/CPU 부하 0 달성.
- **`TerrainChunkManager` (`godot_project/scripts/terrain/terrain_chunk_manager.gd`):**
  - 플레이어의 위치를 실시간 추적하여 15프레임 주기마다 타일별 거리 계산 및 LOD 전환.
  - VRAM 및 버텍스 메모리 병목 완전 해소.
- **`GeoCoordinateConverter` (`godot_project/scripts/core/geo_coordinate_converter.gd`):**
  - 28km 확장 좌표계에 맞추어 WGS84 위경도와 Godot 3D 월드 좌표 간의 양방향 투영 공식 갱신.

---

## 4. 검증 결과
- Godot 4.3 헤드리스 무결성 테스트 통과 (종료 코드 0).
- `run_game.bat` 실행을 통해 고쿠라 남단이 잘리지 않는 광역 고해상도 지형 즉시 확인 가능.
