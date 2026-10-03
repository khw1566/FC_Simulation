---
date: 2026-09-28
author: Antigravity
---
# 울산 광역(60km×60km) 3일차 건물 전수 수집 및 Godot 변환 완료 보고서

본 문서는 60km 광역 맵 3일차(Phase 3: 북구 송정·화봉·현대자동차 공단·진장·명촌·호계 권역)의 실측 건물 전수 수집 및 누적 게임 엔진 자산 변환 결과를 기록합니다.

---

## 1. 3일차 작업 요약
- **대상 권역:** 북구 송정지구, 화봉동, 현대자동차 울산공장 공단권역, 진장유통단지, 명촌동, 농소·호계동 전역
- **격자 분할:** 18개 안전 격자 셀 (각 셀 면적 약 9.6 $\text{km}^2$, VWorld 10 $\text{km}^2$ 제한 충족)
- **일일 API 호출 수:** 총 307회 (1일 안전 상한선 700회 이하 엄격 준수)
- **3일차 신규 고유 건물:** 19,994동 수집 완료
- **누적 고유 건물 수:** **88,380동** (1일차 53,882동 + 2일차 14,504동 + 3일차 19,994동, `bd_mgt_sn` 기준 중복 100% 제거)

---

## 2. 통합 데이터 변환 및 자산 갱신 내역
- **변환 파이프라인:** `pipeline/processors/merge_metro_cache.py` (총 46개 셀 캐시 통합)
- **지형 및 수계 매핑:** 16-bit DEM 및 수계 마스크와 결합하여 동천강·태화강 하구 침수 배제 및 정밀 지표면 밀착 고도 계산
- **최종 탑재 건물:** **88,101동** (지형 매핑 및 유효성 검증 완료)
- **반영 파일:** `godot_project/assets/maps/ulsan_metro_60km/buildings_and_roads.json` (기존 도로망 및 교량/터널 데이터 보존 병합, 파일 크기 약 84.95MB)
- **자산 매니페스트 갱신:** `godot_project/assets/maps/ulsan_metro_60km/manifest.json` SHA-256 해시 인덱싱 갱신 완료 (`6039e5e7...`)

---

## 3. 진행 매니페스트 및 차기 일정
- **매니페스트 기록:** `godot_project/assets/maps/ulsan_metro_60km/buildings_cache/manifest_progress.json`
  - 누적 46개 셀(Phase 1 16개 + Phase 2 12개 + Phase 3 18개) 및 88,380개 건물 관리번호 등록 완료
- **차기 에이전트 인계 사항 (4일차):**
  - 대상: Phase 4 (울주군 남부 온산국가산업단지·덕신·서생권역 24개 셀, 약 5.0만 동, 예상 500회 호출)
  - 실행 스크립트: `pipeline/collectors/metro_building_partition_collector.py`
