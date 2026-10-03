# 260923_UlsanRiverTerrainIntegrationReport.md
작성일자: 2026-09-23
작성자: Antigravity

## 1. 개요 및 목적
본 보고서는 울산과학대학교 서부캠퍼스 권역(5km x 5km) 맵에서 확인된 기존 칸몬 해협 수로 데이터 잔존 문제를 완전히 제거하고, 광폭(수십~수백 미터) 하천인 태화강의 유로를 별도의 좁은 3D 리본 오브젝트가 아닌 지형 높이맵(DEM) 평탄화 및 절차적 지형 셰이더 기반 지형 일체형 수면으로 전환한 작업 내역을 기술합니다.

## 2. 식별된 문제점 및 원인 분석
- 잔존 칸몬 해협 수로 데이터: 초기 맵 복제 과정에서 수로 메타데이터 및 `coastlines_and_waterways.json` 경로가 잔류하여, 울산 지형 상공에 칸몬 해협의 좁은 수로 리본 메쉬가 투영되는 현상이 발생했습니다.
- 태화강 하천 폭 표현 한계: 태화강은 강폭이 100m~300m에 이르는 광역 하천이나, 기존 하천 렌더링 모듈(`CoastlineWaterwayManager`)은 고정 8m~18m 폭의 단일 중심선 리본 메쉬로 설계되어 실제 유로 폭을 온전히 표현하지 못하고 지형과의 단차 및 Z-fighting 결함이 발생했습니다.

## 3. 세부 조치 및 엔지니어링 구현 내역
### 3.1 잔존 수로 데이터 완전 격리 및 제거
- `godot_project/assets/maps/ulsan_uc_west/coastlines_and_waterways.json` 파일 영구 삭제.
- `godot_project/assets/maps/ulsan_uc_west/map_meta.json` 내 `coastlines_waterways` 참조를 완전히 제거하고, 정밀 수계 마스크(`ulsan_watermask_8bit.png`) 경로를 정식 등록.
- `godot_project/scripts/water/coastline_waterway_manager.gd`의 `_init_from_map_selection()`에 가드 로직을 적용하여 `current_map_id == "ulsan_uc_west"` 환경에서는 별도 3D 수로 오브젝트 인스턴스화가 원천 차단되도록 방어 로직 구현.

### 3.2 태화강 수계 마스크 및 지형 평탄화(DEM Carving) 파이프라인 구축
- 정밀 수계 마스크 추출 (`pipeline/processors/watermask_processor.py`):
  - 태화강 수역 MultiPolygon(외곽선 및 하중도 내측 링)과 중심선 도로망 및 완충 지대를 결합한 2048x2048 8-bit 수계 마스크 생성 완료 (총 240,627 픽셀 식별).
- 지형 평탄화 수역 정지 (`pipeline/processors/heightmap_processor.py`):
  - 수계 마스크 영역의 고도를 표고 약 0.8m~1.5m 대역으로 평탄화 정지(`_flatten_water_bodies`).
  - 제방 경계는 가우시안 거리 가중치 기반으로 자연스럽게 스무딩 연결하여 절벽식 단차 왜곡 방지.
- 파이프라인 일괄 실행기 개발 (`tools/apply_taehwa_river_integration.py`):
  - 16-bit 평탄화 높이맵(`ulsan_heightmap_16bit.png`) 갱신.
  - 전술 지도(`ulsan_vector_tactical_map.png`) 및 SVG 벡터 풋프린트 동기화 완료.

### 3.3 절차적 지형 셰이더 일체형 수면 표현 (`procedural_terrain.gdshader`)
- 태화강 수역(`water_mask > 0.02`)에 대해 지형 표면 자체를 짙은 청록색 흐르는 강물 알베도(`ALBEDO`)로 블렌딩.
- 거칠기(Roughness)를 0.08로 축소하고 메탈릭 스펙큘러(0.65)를 적용하여 잔물결 반사광 동적 렌더링.
- 수면 위를 가로지르던 등고선 시각 왜곡을 억제(`water_suppression = 1.0 - smoothstep(0.02, 0.25, water_mask)`)하여 정적인 수면 가독성 확보.

## 4. 검증 결과
- 울산 수계 마스크 검증: `godot_project/assets/maps/ulsan_uc_west/ulsan_watermask_8bit.png` 유효 픽셀 240,627개 정상 식별.
- 16-bit 높이맵 검증: 수계 구역 평균 16-bit 높이값 1562 (실제 표고 기준 약 1.0m 수준)로 안정적인 수평 수역 평탄화 확인.
- 오브젝트 무결성: 울산 맵 구동 시 좁은 리본 메쉬 형태의 수로 오브젝트가 생성되지 않으며, 추가 드로우콜 없이 지형 셰이더 1패스로 광폭 태화강 전 구역이 지형과 일체화되어 렌더링됨을 확인.
