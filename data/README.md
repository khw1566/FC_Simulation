# API 및 외부 기반 데이터 설정 안내 (API & Raw Data Guide)

- 작성일자: 2026년 09월 17일
- 관리 디렉터리: `data/`

---

## 1. 개요
본 프로젝트는 간몬 해협(시모노세키-고쿠라)의 지형, 해안선, 수계 데이터를 사람의 개입 없이 자동으로 수집 및 변환합니다. 이를 위해 필요한 외부 데이터 소스 규격과 API 키 발급 가이드입니다.

---

## 2. API 키 및 설정 (선택/권장)

### 2.1. OpenTopography API (고정밀 DEM 수집용)
- **용도:** NASA SRTM(30m), Copernicus DEM(30m/90m) 등의 고도 데이터를 자동 수집할 때 사용합니다.
- **필요성:** 기본 공용 엔드포인트는 호출 제한(Rate Limit)이 있으므로, 대용량 타일을 연속 다운로드할 때 API 키 등록을 권장합니다.
- **발급처:** [OpenTopography 계정 등록 페이지](https://opentopography.org/)
- **설정 방법:** 발급받은 API 키를 `data/api_keys.json`에 기입합니다.
```json
{
  "opentopography_api_key": "YOUR_API_KEY_HERE"
}
```

### 2.2. OpenStreetMap Overpass API (수계/해안선 수집용)
- **용도:** 간몬 해협의 해안선(`natural=coastline`) 및 하천망(`waterway=river`) 벡터 GeoJSON을 수집합니다.
- **필요성:** **API 키 불필요.** 공개 공용 서버(overpass-api.de 등)를 파이프라인에서 자동 호출합니다.

### 2.3. VWorld API (태화강 둔치 정밀 지형)
- **용도:** `pipeline/processors/taehwagang_terrain/generate.py`가 VWorld 3D 지형 DEM을 수집합니다.
- **설정 방법:** 환경변수 `VWORLD_API_KEY`를 우선 사용하고, 없으면 `data/api_keys.json`의 `vworld_api_key`를 사용합니다. 키는 커밋하지 않습니다.

---

## 3. 사용자가 직접 수동 배치할 수 있는 오프라인 데이터 (선택 사항)

인터넷 수집 대신 이미 보유하고 있거나 더 정밀한 고해상도 데이터를 사용하고자 할 경우, 다음 폴더에 파일을 직접 배치하면 파이프라인이 최우선으로 이를 인식합니다.

- **고도 래스터 파일 (DEM):**
  - 경로: `data/dem/`
  - 지원 포맷: GeoTIFF(`.tif`), HGT(`.hgt`), 16-bit PNG
  - 비고: 시모노세키/고쿠라 좌표계(WGS84, EPSG:4326) 기반 DEM
- **수계/해안선 벡터 파일 (OSM/SHP):**
  - 경로: `data/waterways/`
  - 지원 포맷: GeoJSON(`.geojson`), Shapefile(`.shp`)
- **위성 텍스처 (선택):**
  - 경로: `data/satellite/`
  - 지원 포맷: GeoTIFF, PNG/JPG
