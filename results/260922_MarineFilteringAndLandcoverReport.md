# 260922_MarineFilteringAndLandcoverReport.md
날짜: 2026-09-22
작성자: Antigravity AI Engineering Team

## 1. 개요 및 배경
- 기존 SegFormer 및 단순 분광 임계치 기반 토지 피복 분류기에서 해양 수역이 산림(Forest)으로 오분류되고, 해안가 도회지가 정상 검출되지 않는 문제가 확인되었습니다.
- 국토지리원(GSI) 정사영상 분광 데이터와 수치표고모델(COP30 DEM)의 해수면 기준값을 융합하여, 해양 영역을 1순위로 마스킹/배제하고 육상 영역 내에서 도회지, 산림, 농경지를 재분할하는 알고리즘을 적용하였습니다.

## 2. 해양 필터링 및 육상 피복 재분류 알고리즘
- **해양(Sea) 1차 완전 격리:**
  - 조건: 해발 고도 $\le 0.2\text{m}$ (수치표고) 및 위성 청색 채널 우세 구역($(B > R+22) \cap (B > G+8) \cap (R < 85)$) 융합
  - 효과: 해양 영역($54.23\%$)을 Water 채널(A)로 $100\%$ 고정하고 산림(R), 농경지(G), 도회지(B) 채널을 완전 $0$으로 배제.
- **도회지(Urban, B채널) 복원:**
  - 저고도 평탄지($\text{Elevation} < 120\text{m}$) 중 중립 회색 톤($|R-G| < 25, |G-B| < 25$) 및 인공 구조물 고반사율($\text{Brightness} > 125$) 융합 판정.
  - 시모노세키 도심 및 고쿠라 역세권 도회지 비율 $12.60\%$ 확보.
- **산림(Forest, R채널) 영역 정상화:**
  - 고도 $140\text{m}$ 이상 고지대 산악 및 식생 지수 우세 구역으로 한정하여 $15.26\%$로 정밀 축소.
- **농경지/개활지(Farmland, G채널):**
  - 잔여 완경사 구릉지 및 평탄 녹지 $17.91\%$ 배정.

## 3. 갱신된 지표 피복 면적 통계

| 피복 범례 | 스플랫맵 채널 | 면적 비율 | 주요 해당 구역 |
| :--- | :--- | :--- | :--- |
| **해양/수역 (Sea/Water)** | Alpha (A) | **54.23%** | 간몬 해협 주항로, 세토내해, 동해 연안 |
| **농경지/개활지 (Farmland)** | Green (G) | **17.91%** | 완경사 구릉지, 전답, 녹지대 |
| **산림/산악 (Forest)** | Red (R) | **15.26%** | 히노야마, 아다치산, 카자시산 등 산악 능선 |
| **도회지/건물 (Urban)** | Blue (B) | **12.60%** | 시모노세키 항만 도심, JR 고쿠라/모지코 역세권 |

## 4. 자산 동기화 및 인덱싱 내역
- 갱신 파일: [`kanmon_splatmap_rgba.png`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/kanmon_straits/kanmon_splatmap_rgba.png) (4096 x 4096 RGBA 8-bit)
- 서브 맵 동기화: [`shimonoseki_port_3km/port_splatmap_rgba.png`](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/assets/maps/shimonoseki_port_3km/port_splatmap_rgba.png)
- 매니페스트 인덱싱: `manifest.json` 해시값 및 용량 갱신 완료
