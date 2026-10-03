# 260923_VWorldMugeoBuildingReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 위성 영상 분할 추출 방식 대신, 디지털 트윈국토(VWorld) 국가공간정보포털 건물통합정보(도형) API(`LT_C_SPBD`)를 직접 연동하여 울산광역시 남구 무거동(울산과학대학교 서부캠퍼스 및 울산대학교 권역)의 정밀 실측 건물 풋프린트와 층수 데이터를 수집하고 3D 박스 건물로 배치한 결과를 기록합니다.

## 2. 데이터 출처 및 API 연동
- **수집 데이터원:** 디지털 트윈국토(VWorld) Data API 2.0 (`LT_C_SPBD`, 국가공간정보포털 건물통합정보 도형)
- **적용 API 키:** `6D7B8894-BC4D-43C0-A5F3-9BA01DAD2E8A`
- **조회 영역 (무거동 핵심 권역):**
  - South: 35.5350°N
  - North: 35.5550°N
  - West: 129.2450°E
  - East: 129.2680°E
  - 울산과학대 서부캠퍼스, 울산대학교, 무거동 주거 및 상업지역 포괄

## 3. 처리 및 변환 내역
- **수집기 구현 ([vworld_building_collector.py](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/collectors/vworld_building_collector.py)):**
  - 페이지당 100건 단위 페이징 및 속도 제어를 적용하여 총 3,000건의 실측 지적 건물 폴리곤 및 속성 전수 수집 완료.
- **가공기 구현 ([vworld_building_processor.py](file:///c:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/vworld_building_processor.py)):**
  - 다각형 외부 링(External Ring) 정점 좌표를 추출하여 로컬 월드 5,000m 좌표계로 정확히 투영.
  - 정밀 바이리니어 DEM 보간을 통해 지표면 고도(`base_y`)를 정확히 산출하고, 수계 마스크 영역 내 중복 생성 배제.
  - 건축물 속성의 지상 층수(`gro_flo_co`)를 반영하여 실측 층수 기반 높이(`height = floors * 3.3m + 0.5m`) 계산.

## 4. 데이터 통계 및 결과
- **총 생성 건물 수:** 3,000동 (무거동 주거/상가/캠퍼스 건물)
- **층수 분포:** 최저 1층 ~ 최고 41층 (아파트 및 고층 복합빌딩)
- **건물 높이 분포:** 최저 3.8m ~ 최고 135.8m
- **지표면 표고(Base Y):** 7.27m ~ 123.46m (평지부터 구릉지까지 지형 밀착 완벽 배치)
- **산출 파일:** `godot_project/assets/maps/ulsan_uc_west/buildings_and_roads.json`
- **매니페스트 및 맵 연동:** `map_meta.json` 및 `manifest.json` 등록 완료
