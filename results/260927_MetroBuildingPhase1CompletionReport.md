---
date: 2026-09-27
author: Antigravity
---
# 울산 광역(60km×60km) 1일차 건물 전수 수집 및 Godot 변환 완료 보고서

본 문서는 일일 API 호출 한도를 준수하면서 진행된 60km 광역 맵 1일차(Phase 1: 도심 핵심부)의 실측 건물 전수 수집 및 게임 엔진 자산 변환 결과를 기록합니다.

---

## 1. 1일차 작업 요약
- **대상 권역:** 남구 삼산동·달동·무거동, 중구 성남동·태화동 등 도심 핵심 시가지
- **격자 분할:** 16개 안전 격자 셀 (각 셀 면적 약 5.7 $\text{km}^2$, VWorld 1회 면적 제한 10 $\text{km}^2$ 완벽 충족)
- **일일 API 호출 수:** 총 554회 (1일 안전 상한선 700회 이하 엄격 준수)
- **수집된 고유 건물 수:** **53,882동** (국가 건물관리번호 `bd_mgt_sn` 기준 중복 100% 제거)

---

## 2. 데이터 변환 및 자산 갱신 내역
- **변환 파이프라인:** `pipeline/processors/merge_metro_cache.py` -> `VWorldBuildingProcessor`
- **지형 및 수계 결합:** 16-bit DEM 고도맵 및 8-bit 수계 마스크와 연계하여 침수 건물 자동 제외 및 정밀 지표면 고도 매핑
- **최종 탑재 건물:** **53,703동** (지형 매핑 및 유효성 검증 완료)
- **반영 파일:** `godot_project/assets/maps/ulsan_metro_60km/buildings_and_roads.json` (기존 도로망 및 교량/터널 데이터 보존 병합)

---

## 3. 진행 매니페스트 및 차기 일정
- **매니페스트 기록:** `godot_project/assets/maps/ulsan_metro_60km/buildings_cache/manifest_progress.json`
  - 완료된 16개 셀 ID 및 53,882개 건물 관리번호 캐싱 완료
- **차기 에이전트 인계 사항 (2일차):**
  - 대상: Phase 2 (동구 해안/방어진/현대중공업 12개 셀, 약 4.5만 동, 예상 450회 호출)
  - 실행 명령: `metro_building_partition_collector.py`의 phase2 그리드 가동
