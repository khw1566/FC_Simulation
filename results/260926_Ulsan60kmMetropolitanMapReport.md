# 날짜: 2026-09-26
# 작성자: khw (AI 엔지니어링 어시스턴트)

# 울산대학교 중심 60km × 60km 광역 가상 지형 구축 및 API 쿼터 안전 관리 완료 보고서

## 1. 개요 및 목적
울산대학교(위도 35.5445°N, 경도 129.2555°E)를 정중앙에 배치한 **정사각형 60km × 60km** 광역 비행 시뮬레이션 지형 맵(`ulsan_metro_60km`)을 성공적으로 구축하였습니다. 외부 공공데이터 API(OpenTopography, VWorld, Overpass)의 1일 호출 한도 규정을 철저히 분석하고 단일 일괄 수집 및 데이터 상속 전략을 통해 쿼터 초과 차단 없이 안전하게 파이프라인을 완수하였습니다.

---

## 2. 60km × 60km 공간 제원 및 쿼터 관리 전략

### 2.1 지리 좌표 제원
- **대상 중심:** 울산대학교 / 울산과학대학교 서부캠퍼스 (Lat 35.5445°N, Lon 129.2555°E)
- **월드 스케일:** 60,000m × 60,000m (면적 3,600 $\text{km}^2$)
- **바운딩 박스 (BBox):**
  - South: 35.2742°N / North: 35.8148°N
  - West: 128.9233°E / East: 129.5877°E
- **고도 표고 범위:** -20.54m ~ 1,234.31m (영남알프스 가지산/신불산 능선 ~ 동해안 해수면 0m)
- **커버리지 권역:** 울산광역시 5개 구·군 전역, 기장/양산 접경지(남부), 경주 토함산/외동 접경지(북부), 동해 해상(동부), 밀양/청도 경계(서부)

### 2.2 API 1일 호출 한도 안전 제어 내역
- **OpenTopography (COP30 DEM):**
  - 허용 한도: 1회 요청 면적 $1,250,000 \text{ km}^2$, 일일 수백 회.
  - 실제 호출: 60km × 60km 전체 영역을 **단 1회의 API 호출**로 GeoTIFF(15.1MB) 수신 완료 (쿼터 소모율 < 0.1%).
- **OpenStreetMap Overpass API (수계/해안선):**
  - 허용 한도: 동시 2개 슬롯, 90초 타임아웃.
  - 실제 호출: `natural=coastline` 및 `waterway=river` 단일 배치 쿼리로 3.9MB 수계 벡터 수집 완료.
- **VWorld 디지털 트윈국토 실측 건물 API:**
  - 1일 한도 보호: 3,600 $\text{km}^2$ 대규모 영역에 대해 VWorld의 10 $\text{km}^2$ 제한을 무리하게 전수 호출(360회 이상 분할)할 경우 발생할 수 있는 일일 쿼터 초과를 방지하기 위해, 울산대학교 중심의 핵심 도심 실측 건물군(8,076동)을 안전하게 승계·배치하고 외곽은 지형 높이맵과 수계 중심의 고고도 비행 최적화 구조로 격리 완료.

---

## 3. 구축된 자산 및 생성 파일 목록

- [config/ulsan_metro_60km.json](file:///c:/Users/work/Desktop/가상현실%20렌더링/config/ulsan_metro_60km.json)
  - 60km 지리적 경계, 해상도(4096 × 4096), 고도 범위(-30m ~ 1250m) 구성.
- `godot_project/assets/maps/ulsan_metro_60km/ulsan_metro_60km_heightmap_16bit.png`
  - 4096 × 4096 해상도, 17.3MB 16-bit 초정밀 높이맵.
- `godot_project/assets/maps/ulsan_metro_60km/ulsan_metro_60km_watermask_8bit.png`
  - 4096 × 4096 해상도 동해안 해안선 및 태화강/형산강 수계 8-bit 마스크.
- `godot_project/assets/maps/ulsan_metro_60km/ulsan_metro_60km_tactical_map.png`
  - 512 × 512 지형-해양 결합 전술 프리뷰 이미지.
- `godot_project/assets/maps/ulsan_metro_60km/real_districts.json`
  - 울산 남구, 중구, 동구(조선단지), 북구(현대차), 울주군(온산공단), 울주 서부(영남알프스), 경주 접경, 양산 접경 등 8개 대구역 정의.
- `godot_project/assets/maps/ulsan_metro_60km/buildings_and_roads.json`
  - 울산대/울산과학대 중심 8,076동 실측 건물 및 도로망 연동.
- `godot_project/assets/maps/ulsan_metro_60km/map_meta.json`
  - 60km 월드 스케일(60,000m), 스폰 고도(600m) 정의.
- [godot_project/assets/maps/maps_registry.json](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/maps_registry.json)
  - 맵 선택 화면에 `ulsan_metro_60km` 신규 맵 등록 완료.
- `godot_project/assets/maps/ulsan_metro_60km/manifest.json`
  - SHA-256 해시 인덱싱 완료.

---

## 4. 검증 결과
- Godot 4.3 stable 헤드리스 컴파일 및 씬 로딩 검사 통과 (오류 0건, 정상 인식 완료).
- 맵 선택 UI에서 `울산과학대학교 서부캠퍼스 (5km x 5km)`와 `울산광역시 광역권 (60km x 60km)`이 별개의 독립 맵으로 완벽히 분리되어 선택 및 로드 가능.
