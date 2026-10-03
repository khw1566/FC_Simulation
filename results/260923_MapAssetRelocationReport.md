# 260923_MapAssetRelocationReport.md
작성일자: 2026-09-23
작성자: Antigravity AI

## 1. 개요
본 보고서는 울산 맵과 칸몬 해협 맵 간의 건물 자산 데이터 경로 혼선 및 미반영 상태를 바로잡고, 각 맵이 본래 의도된 고유의 정밀 건물 데이터를 정확히 로드하도록 격리 및 동기화한 조치 내역을 기록합니다.

## 2. 원인 분석
- 파이프라인에서 생성한 칸몬 해협의 36,094개 전수 고정밀 건물 데이터는 공용 산출 디렉터리(`godot_project/assets/generated/buildings_and_roads.json`)에 생성되어 있었습니다.
- 반면 칸몬 해협 전용 맵 폴더(`godot_project/assets/maps/kanmon_straits/buildings_and_roads.json`)에는 과거의 3,370개 저해상도 샘플 데이터가 그대로 유지되어 있어, 칸몬 해협 로드 시 구버전 건물이 출력되었습니다.
- 울산 맵은 VWorld 실측 3,000동 건물 데이터가 전용 폴더(`godot_project/assets/maps/ulsan_uc_west/buildings_and_roads.json`)에 정상 배치되어 고정밀로 렌더링되고 있었으나, 공용 생성 폴더와 맵 폴더 간의 버전 불일치로 혼선이 발생했습니다.

## 3. 조치 내역
1. **칸몬 해협 정밀 건물 데이터 동기화:**
   - 36,094동 전수 실측 건물 및 1,157개 도로/터널 데이터(`assets/generated/buildings_and_roads.json`)를 칸몬 해협 맵 디렉터리(`godot_project/assets/maps/kanmon_straits/buildings_and_roads.json`)로 복사 및 동기화 완료 (25.7MB).
2. **울산과학대 서부캠퍼스 맵 건물 데이터 격리:**
   - 무거동 VWorld 공공데이터 3,000동 건물 데이터가 `godot_project/assets/maps/ulsan_uc_west/buildings_and_roads.json`에 완벽히 격리되어 유지됨.
3. **각 맵별 메타데이터 및 매니페스트 인덱싱 갱신:**
   - `kanmon_straits`: 건물 36,094개 / 도로 1,157개 연결 확인.
   - `ulsan_uc_west`: 건물 3,000개 연결 확인.
   - 각 맵 폴더의 `manifest.json` SHA-256 해시 재인덱싱 완료.
