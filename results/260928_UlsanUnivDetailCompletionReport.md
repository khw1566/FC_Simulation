---
date: 2026-09-28
author: Antigravity
---
# 울산과학대 및 울산대 고화질 캠퍼스(보도·태양광·수목) 구축 완료 보고서

본 문서는 울산과학대학교 서부캠퍼스 및 울산대학교 권역(5km×5km)의 지형 및 건물 품질을 극대화하고, 단순 건물을 넘어 보도블록/광장 타일, 옥상 태양광 발전 모듈, 4.8만 본 이상의 수목 생태계를 게임 엔진 런타임에 탑재 완료한 결과를 기록합니다.

---

## 1. 세부 인프라 데이터 합성 및 자산 생성 결과
- **합성 파이프라인:** `pipeline/processors/campus_detail_synthesizer.py`
- **1) 옥상 태양광 발전 패널 어레이:**
  - 대상: 울산과학대 창의관·공학관 및 울산대 학생회관/자연대 등 옥상 면적 280㎡ 이상 건물 전수
  - 생성 수량: **942개 동** 옥상 태양광 어레이
  - 기하 제원: 1.95m × 1.15m 셀 패널, 정남향(180°) 15도 경사각 배치
- **2) 보도블록 및 캠퍼스 광장 타일:**
  - 도로변 양측 보도블록: **11,863개 세그먼트** (폭 2.2m)
  - 캠퍼스 중앙 광장: **5개 대형 광장** (울산과학대 서부캠퍼스 중앙광장, 공학관 전면로, 울산대 정문광장, 중앙도서관 시계탑광장, 해송홀 보행로)
- **3) 캠퍼스 및 가로수 식생 (Tree & Foliage):**
  - 총 식재 수목: **48,545본**
  - 가로수(느티나무형 활엽수): 도로변 12m 간격 정렬 배치
  - 캠퍼스 조경수 및 완충림(소나무형 침엽수): 문수산 자락 및 교내 녹지대 군락 배치
- **산출 파일:** `godot_project/assets/maps/ulsan_uc_west/campus_details.json` 및 `campus_splatmap.png`

---

## 2. Godot 4 3D 렌더링 엔진 구현 내역
1. **옥상 태양광 모듈 빌더 ([SolarArrayBuilder](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/solar_array_builder.gd)):**
   - 다크 네이비 블루 PBR 메탈릭(0.85), 러프니스(0.18), 클리어코트(0.8)를 적용하여 태양 위치에 따른 실시간 솔라 패널 반사광 표현.
2. **보도 및 광장 서피스 빌더 ([PavementMeshBuilder](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/pavement_mesh_builder.gd)):**
   - 지형 표면 위 5~8cm 상단 부양 삼각망 메쉬 구성 및 타일 텍스처 노멀 매핑 적용.
3. **GPU 일괄 인스턴싱 매니저 ([FoliageMultiMeshManager](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/foliage_multi_mesh_manager.gd)):**
   - 4.8만 본의 나무를 `MultiMeshInstance3D` 2개로 압축하여 60FPS 방어 및 드로우콜 2회로 통제.
4. **미풍 흔들림 셰이더 ([foliage_wind.gdshader](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/shaders/foliage_wind.gdshader)):**
   - 버텍스 높이에 비례한 사인파 미풍 시뮬레이션 적용.
5. **오케스트레이터 통합:**
   - [BuildingRoadManager](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/terrain/building_road_manager.gd)에서 맵 로드 시 `campus_details.json`을 자동 감지하여 일괄 렌더링.

---

## 3. 검증 및 무결성 확인
- **Godot 정적 검사:** `tools/godot/Godot_v4.3-stable_win64.exe --check-only` 결과 오류 0건 통과.
- **자산 매니페스트:** [manifest.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/manifest.json) SHA-256 해시 인덱싱 갱신 완료.
- **모듈 인덱스:** [module_index.json](file:///c:/Users/khw/Desktop/가상현실%20렌더링/module_index.json) 신규 3개 클래스 등록 완료.
