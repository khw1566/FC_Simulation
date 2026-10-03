# [260921] 해안선 선명화 및 항만 기초 최적화 인덱싱 진행 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 해안선 뭉개짐 원인 분석 및 해결 방안

- **기존 문제 원인:**
  1. 청크 버텍스 해상도가 타일당 128x128에 불과하여 7km 폭 타일 기준 버텍스 간격이 약 55m로 넓어 급격한 부두/방파제 단차를 표현하지 못함.
  2. 절차적 셰이더의 해수면 부근(Y=-0.5m ~ +1.5m) 텍스처 전이 대역이 완만하여 해안선과 모래사장이 흐리게 퍼지는 블렌딩 현상 발생.
  3. LOD 0 적용 반경(4.5km)이 좁아 항구 건너편이나 만(Bay) 건너편 해안선이 조기에 저해상도 LOD로 강등됨.
- **적용된 기술 조치:**
  1. **버텍스 밀도 4배 상향:** LOD 0 그리드 해상도를 **256 × 256**으로 확대하여 격자 간격을 약 27m 정밀도로 축소.
  2. **해안선 단구 및 호안 직벽 대역 셰이더 재설계:** Y=0m 접점에 콘크리트/암벽 급경사 블렌딩을 0.6m 내에서 가파르게 전이시켜 항만과 해수면 간 경계를 뚜렷하게 분리.
  3. **LOD 유효 반경 확대:** LOD 0 유지 거리를 기존 4.5km에서 **7.0km**로, LOD 1을 **14.0km**로 상향하여 간몬 해협 양안(시모노세키-모지-고쿠라) 전역을 최고 해상도로 조망 가능.

---

## 2. 갱신된 자산 및 모듈 인덱싱 현황

| 자산 식별자 | 파일 경로 | 해상도 / 포맷 | 설명 |
| :--- | :--- | :--- | :--- |
| **`heightmap_16bit`** | `godot_project/assets/generated/kanmon_heightmap_16bit.png` | 4096 × 4096 (16-bit PNG) | 고쿠라 전역 및 시모노세키 포함 초고해상도 높이맵 |
| **`tiles_index`** | `godot_project/assets/generated/tiles/tiles_index.json` | 16개 타일 메타데이터 | 4×4 타일 그리드 분할 좌표 및 고도 정규화 인덱스 |
| **`terrain_tiles`** | `godot_project/assets/generated/tiles/tile_{x}_{y}.png` | 타일당 1024 × 1024 (16-bit) | 동적 스트리밍용 분할 타일셋 |
| **`watermask_8bit`** | `godot_project/assets/generated/kanmon_watermask_8bit.png` | 4096 × 4096 (8-bit PNG) | OSM 기반 간몬 해협 및 하천 수계 마스크 |
| **`real_districts`** | `godot_project/assets/generated/real_districts.json` | JSON (842개 행정동) | 시모노세키 및 기타큐슈 상세 행정구역 폴리곤 |
| **`vector_tactical_map`** | `godot_project/assets/generated/kanmon_vector_tactical_map.png` | 2048 × 2048 PNG | 등고선, 철도, 도로, 항만 인프라 벡터 지도 |
| **`manifest`** | `godot_project/assets/generated/manifest.json` | JSON (SHA-256 포함) | 전체 자산 무결성 추적 매니페스트 |

---

## 3. 핵심 스크립트 모듈 구조

- `TerrainChunk` (`terrain_chunk.gd`): 256/128/64 동적 LOD 메쉬 생성 및 근거리 물리 충돌체 바인딩.
- `TerrainChunkManager` (`terrain_chunk_manager.gd`): 플레이어 기준 7km/14km/28km 반경별 청크 LOD 및 컬링 제어.
- `GeoCoordinateConverter` (`geo_coordinate_converter.gd`): 28km 광역 스케일 WGS84 위경도와 Godot 월드 좌표 간 정밀 변환.
- `procedural_terrain.gdshader`: 0m 수면 직벽 콘크리트/호안 셰이딩 및 등고선 오버레이.
- `kanmon_water_manager.gd`: 32km 광역 해수면 평면 배치.

---

## 4. 검증 결과
- Godot 4.3 헤드리스 무결성 테스트 종료 코드 0으로 정상 통과.
- `run_game.bat` 실행 시 해안선과 항구 인근 단차가 또렷하게 분리된 3D 가상 지형 확인 가능.
