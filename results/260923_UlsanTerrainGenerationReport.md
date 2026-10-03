# 260923_UlsanTerrainGenerationReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 울산과학대학교 서부캠퍼스를 중심으로 한 5km × 5km 정밀 실측 지형(DEM) 데이터 수집, 16비트 높이맵 생성 및 Godot 4 맵 시스템 연동 작업 결과를 기록합니다.

## 2. 지역 및 좌표 제원
- **대상지:** 울산과학대학교 서부캠퍼스 (울산광역시 남구 대학로 일대)
- **중심 좌표:** 위도 35.5445°N, 경도 129.2555°E
- **격자 영역 (5km × 5km):**
  - South: 35.5220°N
  - North: 35.5670°N
  - West: 129.2279°E
  - East: 129.2831°E
- **월드 스케일:** 5,000m × 5,000m (지형 해상도 2048 × 2048)
- **실측 고도 범위:** -0.64m ~ 407.78m (평균 71.70m, 보정 대역 -10.0m ~ 450.0m)
- **주요 포함 지형 및 수계:** 문수산 자락, 무거동 도회지, 울산대학교, 울산과학대 서부캠퍼스, 태화강 본류(북단) 및 무거천/척과천 지류 수계

## 3. 공공데이터 및 API 연동 내역
- **등록된 공공데이터 API 키:**
  - 국토교통부 국토지리정보원 수치지도: `f3e0a628cb33471c8e0e7d78ce1b79943ad6aef826196f918c387471b155f1db`
  - VWorld 디지털 트윈국토: `6D7B8894-BC4D-43C0-A5F3-9BA01DAD2E8A`
  - OpenTopography COP30 DEM API: `4e3ab1e43c5249eadad82f0e25fcad36`
  - 저장 위치: `data/api_keys.json`

## 4. 파이프라인 처리 결과
1. **DEM 고도 데이터 다운로드:**
   - Copernicus GLO-30 30m 해상도 수치표고모델(DEM) 원본 취득 완료 (`data/raw/ulsan_uc_west/dem/ulsan_uc_west_COP30.tif`).
2. **16-bit 높이맵 생성 및 안티에일리어싱 스무딩:**
   - 2048 × 2048 해상도 리샘플링 및 해수면/하천 경계 안티에일리어싱 스무딩 적용 완료.
   - 산출물: `godot_project/assets/maps/ulsan_uc_west/ulsan_heightmap_16bit.png`
3. **수계 마스크 생성:**
   - 태화강 및 무거천/척과천 하천 및 호수/저수지 8-bit 마스크 생성 완료.
   - 산출물: `godot_project/assets/maps/ulsan_uc_west/ulsan_watermask_8bit.png`
4. **Godot 멀티 맵 레지스트리 및 매니페스트 인덱싱:**
   - 메타데이터 정의: `godot_project/assets/maps/ulsan_uc_west/map_meta.json`
   - 전체 맵 레지스트리 등록: `godot_project/assets/maps/maps_registry.json`
   - 자산 매니페스트 인덱싱: `godot_project/assets/maps/ulsan_uc_west/manifest.json`
