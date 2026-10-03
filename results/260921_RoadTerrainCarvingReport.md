# [260921] 도로/건물 지형 간섭 해소 및 상부 지형 절토(Carving) 최적화 리포트

- 작성일자: 2026년 09월 21일
- 작성자: Antigravity AI

---

## 1. 개요 및 원인 분석
- **문제점 분석:**
  - 16비트 높이맵의 지형 표면과 도로 리본 및 건물 박스 메시가 동일한 표고 대역을 공유하여 심각한 Z-fighting 및 지형 파묻힘 현상 발생.
  - 경사지나 굴곡 지형에서 도로가 지형 아래로 파고들거나 건물의 하부가 지형 밖으로 드러나는 간섭 문제 확인.
- **해결 대책:**
  - **도로 및 건물 부지 절토(Carving):** 높이맵 생성 단계에서 도로 선형을 따라 상부 지형을 0.8m 절토하고 주변부를 스무딩 처리. 건물 부지는 0.4m 정지 작업 수행.
  - **렌더링 우선권(Render Priority) 및 뎁스 제어:** 건물(`render_priority = 2`), 도로(`render_priority = 1`, `DEPTH_DRAW_ALWAYS`)를 부여하여 GPU 래스터화 시 지형보다 항상 전면에 우선 렌더링되도록 보장.
  - **건물 기초 연장 및 도로 표고 오프셋:** 건물의 바닥면을 지형 하부 -2.0m까지 연장하여 경사지 안착성을 확보하고, 도로는 노면 기준 +1.2m 고도 오프셋을 적용하여 지형 돌출 방지.

---

## 2. 모듈별 변경 내역

- [HeightmapProcessor](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/heightmap_processor.py): `_carve_roads_and_buildings()` 메서드를 추가하여 도로 버퍼 영역의 상부 지형 절토 및 가우시안 경사 완화 적용.
- [BuildingRoadProcessor](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/processors/building_road_processor.py): 정밀 바이리니어 서브픽셀 고도 보간 알고리즘 적용 및 도로 노면 +1.2m 안전 오프셋 부여.
- [BuildingRoadManager](file:///C:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd): 모노크롬 재질에 `render_priority`, `depth_draw_mode`를 설정하고 건물 하부 지중 연장 구조 적용.
- [run_pipeline.py](file:///C:/Users/khw/Desktop/가상현실%20렌더링/pipeline/run_pipeline.py): 도로/건물 데이터를 먼저 수집한 후 높이맵 절토 프로세스에 전달하도록 파이프라인 단계 순서 재조정.

---

## 3. 검증 결과
- 파이프라인 전 프로세스 원클릭 자동 실행 완료.
- 도로 1,157개 구간 및 건물 972개 부지에 대한 절토 완료 높이맵(`kanmon_heightmap_16bit.png`) 재생성.
- Godot 4.3 헤드리스 엔진 프로젝트 컴파일 검증 완료 (Exit Code 0).
