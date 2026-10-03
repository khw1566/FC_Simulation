---
date: 2026-09-28
author: Antigravity
---
# 울산과학대 서부캠퍼스 및 울산대학교 권역 극고화질 디지털 트윈 고도화 계획서

본 문서는 울산과학대학교 서부캠퍼스와 울산대학교 일대(5km×5km 핵심 권역)의 지형 정밀도 및 건물 품질을 극도로 끌어올리고, 단순 박스형 건물을 넘어 바닥 타일·보도블록, 옥상 태양광 발전 패널, 수목·초목 생태계 및 캠퍼스 특화 시설물을 체계적으로 구축하기 위한 5단계 엔지니어링 실행 계획을 정의합니다.

---

## 1. 개요 및 목표

### 1.1 대상 공간 제원
- **대상 구역:** 울산과학대학교 서부캠퍼스 및 울산대학교(무거동 일대, [ulsan_uc_west.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/config/ulsan_uc_west.json))
- **공간 범위:** 남위 35.5220° ~ 북위 35.5670°, 서경 129.2279° ~ 동경 129.2831° (5.0km × 5.0km = 25.0 $\text{km}^2$)
- **고도 범위:** -10.0m ~ 450.0m (문수산 능선 및 무거천 저지대 포함)

### 1.2 고도화 핵심 목표
1. **지형 정밀도 극대화:** 광역 30m 해상도 지형을 국토지리정보원 정밀 수치표고모델(DEM 5m) 및 캠퍼스 보도 단차·계단·테라스 레벨로 극세분화.
2. **건물 디테일 고도화:** 단순 단색 압출 메쉬에서 탈피하여 층별 창문 루버, 옥상 난간(Parapet), 옥탑 구조물(엘리베이터 타워/환기덕트), 옥상 태양광 발전 패널(Solar Array) 배치.
3. **지상 바닥재 타일링 및 도로 인터페이스:** 아스팔트 차도, 보도블록 타일, 보행자 전용 보도(인도), 광장 페이빙, 잔디밭 경계 연석(Curb) 정밀 분할.
4. **캠퍼스 식생(Tree & Foliage) 식재:** 위성 정규식생지수(NDVI) 및 OSM 가로수 데이터를 결합한 멀티 메시 인스턴싱(MultiMeshInstance3D) 기반 초목 렌더링.
5. **극고성능 최적화 유지:** 60FPS 방어를 위한 계층적 거리 LOD(LOD 0~2), GPU 하이젠 드로우콜 배치(Batching), 인스턴싱 컬링 파이프라인 수립.

---

## 2. 단계별 상세 실행 계획

### 2.1 정보 수집 (Data Collection)
- **국토지리정보원(NGII) 5m 정밀 수치표고모델(DEM):**
  - 무거동 및 캠퍼스 경사면 지형 격자를 5m급 정밀 래스터로 확보하여 계단식 캠퍼스 단차 표현.
- **국가공간정보 VWorld 건물통합정보(LT_C_SPBD) 정밀 재추출:**
  - 건물 명칭, 용도, 동별 층수 및 상세 다각형 경계선 전수 확보.
- **OpenStreetMap(OSM) 태그 세부 속성 추출:**
  - 보도(`highway=footway/pedestrian`), 광장(`amenity=square`), 주차장(`amenity=parking`), 공원 및 잔디밭(`landuse=grass/recreation_ground`).
  - 식생 라인(`natural=tree`, `natural=tree_row`, `landuse=forest`).
  - 옥상 태양광 패널(`generator:source=solar`, `power=generator`).
- **Sentinel-2 고해상도 NDVI(정규식생지수) 마스크 생성:**
  - 서부캠퍼스 및 울산대 녹지대(아산스포츠센터 뒤편, 문수산 산책로, 교내 수목 밀집지)의 실제 식생 분포 픽셀 마스크(10m 해상도) 산출.

### 2.2 데이터 정제 및 기하 연산 (Data Processing & Geometry Sanitization)
- **식생 포인트 추출기 (`pipeline/processors/foliage_extractor.py` 신규 구축):**
  - NDVI 녹지 영역과 OSM 도로/건물 버퍼(Buffer)를 차집합 연산하여 도로 위나 건물 내부로 나무가 침범하지 않도록 클리핑.
  - 가로수 축선(Tree Row)을 따라 8m 간격 정렬 포인트 생성 및 수목 종류(활엽수/침엽수/관목) 난수 가중치 부여.
- **바닥 포장 및 보도 타일 분할기 (`pipeline/processors/pavement_processor.py` 신규 구축):**
  - 차도 폴리곤(Road Bed), 보도 폴리곤(Sidewalk), 광장 페이빙(Square), 잔디밭(Lawn)을 고유 재질 ID로 레이어링.
  - 2D Voronoi / Delaunay 삼각망 생성을 통해 바닥 메쉬의 스티칭 및 UV 좌표 자동 생성.
- **옥상 태양광 패널 할당기 (`pipeline/processors/rooftop_solar_allocator.py` 신규 구축):**
  - 울산과학대 서부캠퍼스 공학관, 울산대 학생회관/자연대 등 대형 옥상 평면(면적 300㎡ 이상)을 검출.
  - 옥상 중심부에 방위각(정남향 15° 경사각)을 고려한 태양광 모듈 래크(Rack) 그리드 배치 데이터 산출.

### 2.3 3D 절차적 에셋 생성 (Procedural Asset Generation)
- **모듈러 빌딩 메쉬 빌더 고도화 (`building_mesh_builder.gd` 리팩토링):**
  - **스커트 & 파라펫:** 지반 접지 하부 스커트 외에 옥상 외곽 0.9m 난간(Parapet) 자동 생성.
  - **옥탑 구조물:** 옥상 중앙에 층수 비례 박스형 기계실/엘리베이터 타워 자동 배치.
  - **옥상 태양광 어레이:** 1.5m × 1.0m 단위 솔라 패널 지오메트리를 그리드로 생성하고 짙은 네이비 블루 반사 재질 적용.
- **보도 및 바닥 타일 메쉬 빌더 (`scripts/terrain/pavement_mesh_builder.gd` 신규):**
  - 캠퍼스 보도블록(20cm×20cm 타일 노멀맵 및 러프니스 텍스처 타일링).
  - 잔디밭 지반과 보도 사이 15cm 연석(Curb) 단차 절토 메쉬 생성.
- **수목/초목 다형 인스턴스 빌더 (`scripts/terrain/foliage_multi_mesh_manager.gd` 신규):**
  - 3가지 초저폴리(Low-Poly Stylized) 식생 원형 메쉬 생성:
    1. 가로수(느티나무형 활엽수, 약 120 버텍스)
    2. 캠퍼스 조경수(소나무형 침엽수, 약 150 버텍스)
    3. 캠퍼스 잔디/관목 덤불(크로스 쿼드, 8 버텍스)

### 2.4 렌더링 파이프라인 (Rendering Pipeline)
- **하이브리드 지형 셰이더 (`procedural_terrain.gdshader` 확장):**
  - 스플랫맵(Splatmap) RGBA 채널 도입: R=보도블록, G=잔디/초목, B=아스팔트 차도, A=암석/토양.
  - 매크로 텍스처 반복 방지를 위해 거리 기반 안티 타일링(Texture Bombing / Stochastic Sampling) 기법 적용.
- **태양광 패널 머티리얼:**
  - 금속성(Metallic 0.9), 거칠기(Roughness 0.15), 투명 코팅(Clearcoat 0.8)을 부여하여 태양 위치에 따른 실제 태양광 셀 반사광 시뮬레이션.
- **초목 버텍스 셰이더 (`shaders/foliage_wind.gdshader` 신규):**
  - 전역 바람 벡터(`wind_velocity`)에 따른 상단 버텍스 사인파 미풍 흔들림(Wind Swaying) 구현.

### 2.5 최적화 아키텍처 (Optimization Architecture)
- **GPU MultiMeshInstance3D 인스턴싱:**
  - 1만 그루 이상의 캠퍼스 수목을 개별 노드가 아닌 구역별 `MultiMeshInstance3D` 1~2개로 통합하여 드로우콜을 10 미만으로 압축.
- **계층적 시야거리 컬링(Hierarchical Distance Culling):**
  - 잔디/소형 관목: 카메라 거리 300m 이내만 표시.
  - 가로수/조경수: 거리 1,500m 이내 표시 (그 이상은 지형 텍스처 임베딩으로 전환).
  - 옥상 태양광 패널 및 보도블록 세부 타일: 거리 800m 이내만 고화질 메쉬 렌더링.
- **지반 고도 바이리니어 캐싱:**
  - 모든 오브젝트는 씬 로딩 시 지형 높이맵 배열을 바이리니어 샘플링하여 1회만 고도 확정 후 정적 고정(물리 연산 부하 0%).

---

## 3. 구현 세부 규범 및 모듈 설계

```
가상현실 렌더링/
├── pipeline/
│   ├── collectors/
│   │   └── campus_osm_detail_collector.py   # 보도, 광장, 수목, 태양광 패널 OSM 수집기
│   └── processors/
│       ├── pavement_processor.py            # 차도/보도/잔디밭 폴리곤 분할기
│       ├── foliage_extractor.py             # NDVI 및 OSM 결합 식생 좌표 산출기
│       └── rooftop_solar_allocator.py       # 대형 건물 옥상 태양광 어레이 추출기
├── godot_project/
│   ├── assets/maps/ulsan_uc_west/
│   │   ├── campus_details.json              # 보도, 태양광, 수목 통합 배치 파일
│   │   └── campus_splatmap.png              # 2048x2048 지면 재질 분할 마스크
│   ├── scripts/terrain/
│   │   ├── pavement_mesh_builder.gd         # 보도블록 및 광장 3D 서피스 빌더
│   │   ├── foliage_multi_mesh_manager.gd    # MultiMesh 수목 인스턴싱 매니저
│   │   └── solar_array_builder.gd           # 옥상 태양광 구조물 빌더
│   └── shaders/
│       └── foliage_wind.gdshader            # 바람 흔들림 및 라이팅 셰이더
└── results/
    └── 260928_UlsanUnivDetailPlan.md        # 본 계획 문서
```

---

## 4. 추진 일정 및 작업 순서
1. **1단계 (데이터 수집 및 정제):** `campus_osm_detail_collector.py` 및 `foliage_extractor.py` 작성, 캠퍼스 내 세부 요소 GeoJSON 추출.
2. **2단계 (지형 스플랫맵 및 보도 타일링 구축):** `pavement_processor.py`를 통해 보도/차도/잔디 지면 텍스처 스플랫맵 생성 및 지형 셰이더 연동.
3. **3단계 (옥상 태양광 및 건물 디테일 빌더 구현):** `solar_array_builder.gd`를 통해 서부캠퍼스 및 울산대 건물 옥상에 솔라 패널 및 파라펫 배치.
4. **4단계 (수목 MultiMesh 인스턴싱 시스템 구축):** `foliage_multi_mesh_manager.gd` 및 바람 셰이더 적용, 1만 본 이상 식생 렌더링 및 거리 컬링 검증.
5. **5단계 (엔진 통합 빌드 및 성능 프로파일링):** 프레임레이트(60FPS 유지), VRAM 점유율, 드로우콜 한계치 정밀 검증 후 최종 보고서 작성.
