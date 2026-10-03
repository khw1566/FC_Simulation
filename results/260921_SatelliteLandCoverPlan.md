# 260921_SatelliteLandCoverPlan.md
날짜: 2026-09-21
작성자: Antigravity AI Engineering Team

## 1. 개요 및 목적
- 간몬 해협 일대(위도 33.80~34.05, 경도 130.80~131.10)의 고해상도 위성 영상 및 토지 피복(Land Cover) 데이터를 수집하고 분석하여 농경지(논, 밭), 도회지(시가지, 산업단지), 산림/산악, 정밀 하천 및 수변구역을 식별합니다.
- 추출된 다중 스플랫/마스크 데이터를 Godot 4 지형 셰이더 및 바이옴/환경 시스템에 연계하여 사실적인 입체 가상 환경을 구축하기 위한 단계별 기술 계획서입니다.

## 2. 데이터 소스 분석 및 수집 가능성 검토
- **위성 영상 타일 (Satellite Imagery Tiles):**
  - **수집 방식:** 국토지리원(GSI 일본 전자국토 Web 타일: Seamlessphoto 항공/위성 영상) 또는 Sentinel-2 / Landsat-8 공개 API 타일 수집기 구현.
  - **해상도:** Zoom Level 15~16 기준 픽셀당 약 2.4m~4.8m의 트루 컬러 RGB 위성 정사 영상 확보 가능 (4096x4096 정사 모자이크 생성).
- **지표 피복 및 식생 분석 (Land Cover Classification):**
  - **ESA WorldCover 10m / Copernicus Global Land Cover:** 10m 해상도로 전 세계 토지 피복(시가지, 농경지, 산림, 초지, 수역 등)을 11개 클래스로 분류한 공개 래스터 데이터 활용 가능.
  - **OSM Landuse & Natural 벡터 레이어:** `landuse=farmland`, `paddy`, `orchard`, `forest`, `residential`, `industrial`, `waterway=riverbank` 등 정밀 경계선 벡터 병합.
- **정밀 하천망 및 수변구역 (Riverbanks & Riparian Zones):**
  - 단순 중심선(`waterway=river`) 외에 실제 하천 수면 폴리곤(`waterway=riverbank`, `natural=water`) 및 하천 둑길/완충녹지를 분리 추출.

## 3. 단계별 구현 로드맵

### 1단계: 위성 정사 타일 및 토지 피복 수집기 개발 (`pipeline/collectors/`)
- `satellite_collector.py`:
  - 설정된 바운딩 박스(BBox)에 해당하는 위성 타일을 비동기 일괄 다운로드 후 4096x4096 크기의 지리 정합(Geo-referenced) 정사 이미지(`kanmon_satellite_rgb.png`) 합성.
- `landcover_collector.py`:
  - ESA WorldCover 타일 또는 OSM 정밀 Landuse 폴리곤(`farmland`, `forest`, `residential`, `riverbank`)을 일괄 다운로드.

### 2단계: 토지 피복 분류 및 다중 스플랫 마스크 생성 (`pipeline/processors/`)
- `landcover_processor.py`:
  - 위성 RGB 컬러 분석(NDVI 식생 지수 모사, 색상 클러스터링)과 OSM Landuse 벡터 마스크를 융합.
  - **4채널 스플랫맵 (Splatmap Texture) 생성 (`kanmon_splatmap_rgba.png`):**
    - **R 채널:** 산림/수목 (Forest & Mountain Greenery)
    - **G 채널:** 농경지/논밭 (Farmland & Paddy Fields, 파종/경작 격자 패턴)
    - **B 채널:** 도회지/포장면 (Urban, Residential, Industrial)
    - **A 채널:** 수변 완충지/모래/강변 자갈 (Riparian Zone & Shoreline)
- **정밀 하천 마스크 고도화 (`watermask_processor.py` 연계):**
  - 기존 해안선/중심선 기반 마스크에 실제 강폭(Riverbank) 및 조간대 수변구역을 병합하여 16-bit 높이맵 침식과 연동.

### 3단계: Godot 4 지형 셰이더 및 바이옴 시스템 통합 (`godot_project/`)
- **멀티 텍스처 지형 셰이더 확장 (`terrain_splat.gdshader`):**
  - 단일 모노크롬 색상에서 탈피하여 스플랫맵의 RGBA 가중치에 따라 산악(암반/수목 텍스처), 농경지(논두렁/이랑 텍스처), 도회지(아스팔트/콘크리트), 수변구역(모래/자갈)을 자연스럽게 블렌딩.
- **농경지/산림 3D 인스턴싱 시스템 (`biome_manager.gd`):**
  - MultiMeshInstance3D를 활용하여 농경지 영역에는 규칙적인 논밭 구획선 및 시설물을, 산악 영역에는 밀집 수목을 효율적으로 배치(LOD 및 시야각 기반 최적화).

### 4단계: 파이프라인 자동화 및 매니페스트 갱신
- `run_pipeline.py`에 위성 수집 및 토지 피복 처리 단계를 신규 모듈로 등록.
- `godot_project/assets/generated/manifest.json`에 스플랫맵 및 위성 텍스처 메타데이터 자동 인덱싱.

## 4. 즉시 착수 항목
- 사용자 승인 후 **1단계: 위성 이미지 수집기(`satellite_collector.py`) 및 토지 피복 수집기 개발**부터 순차적으로 구현을 개시합니다.
