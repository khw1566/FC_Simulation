날짜: 2026-09-23
작성자: khw (AI 엔지니어링 에이전트)

# 고도별 다층 구름 절차적 합성 및 기후 다양화 구현 완료 보고서

## 1. 개요 및 목적
단순한 형태의 단일 구름 렌더링을 탈피하여, 실제 대기 과학 기반의 4대 고도별 구름 종류(적운, 층적운, 권운, 적란운)를 절차적 생성 노이즈로 구현하고, 이들을 사전 생성된 풀에서 복합 합성하여 7가지 현실적 기상 상태를 동적으로 연출할 수 있도록 시스템을 전면 고도화하였습니다.

---

## 2. 고도별 구름 유형 및 절차적 셰이딩 사양

### 2.1. 셰이더 기반 구름 형태학 구현 (`volumetric_cloud.gdshader`)
- **0: 적운 (Cumulus, 저고도 600m ~ 1,100m)**
  - 하단은 평평하게 응결되고 상단은 돔 형태로 솟구치는 프로파일(`base_flatness * top_dome`).
  - Billow 변환(`1.0 - abs(raw_fbm * 2.0 - 1.0)`)과 뭉침 강도(`puffiness = 1.2`)를 적용하여 솜사탕처럼 단단히 응집된 뭉게구름 코어 형성.
- **1: 층적운 (Stratocumulus, 중고도 1,200m ~ 2,000m)**
  - 하늘을 넓고 낮게 덮는 수평 물결형 덮개구름.
  - 가로 스케일 확장(`pos.y * 2.5`)을 통해 층상 대기 안정층 시각화.
- **2: 권운 (Cirrus, 고고도 2,800m ~ 4,500m)**
  - 고고도 제트기류에 의해 빗자루로 쓸린 듯한 새털 및 깃털 형태.
  - 왜곡 벡터(`curl_factor = 1.2`) 및 거듭제곱(`pow(raw, 2.2)`) 필터링을 통해 얇고 투명한 얼음 결정 실가닥 표현.
- **3: 적란운 (Cumulonimbus, 수직 발달 1,200m ~ 3,500m)**
  - 상층부 모루구름(Anvil) 사방 확산 프로파일(`anvil_spread = 1.0 + smoothstep(0.65, 1.0, vert_t) * 1.5`).
  - 고밀도(`density = 14.0`) 및 어두운 내부 산란 감쇄로 뇌우 구름의 위압감 형성.

---

## 3. 기상 상태 머신 확장 및 구름 합성 비율 (`WeatherManager.gd`)

| 기상 상태 | 적운(Cumulus) | 층적운(Stratocumulus) | 권운(Cirrus) | 적란운(Cumulonimbus) | 강우 및 낙뢰 | 대기 안개/조도 |
|---|---|---|---|---|---|---|
| **0: 쾌청 (Clear)** | 0% | 0% | 0% | 0% | 비 0% / 낙뢰 OFF | 안개 0.00005, 태양 1.25 |
| **1: 맑음/권운 (Cirrus Fair)** | 0% | 0% | 80% | 0% | 비 0% / 낙뢰 OFF | 안개 0.00008, 태양 1.20 |
| **2: 구름 조금 (Partly Cloudy)** | 70% | 20% | 40% | 0% | 비 0% / 낙뢰 OFF | 안개 0.00012, 태양 1.05 |
| **3: 흐림/덮개구름 (Overcast)** | 40% | 100% | 0% | 0% | 비 0% / 낙뢰 OFF | 안개 0.00025, 태양 0.80 |
| **4: 짙은 안개 (Foggy)** | 20% | 60% | 0% | 0% | 비 0% / 낙뢰 OFF | 안개 0.00120, 태양 0.60 |
| **5: 비 (Rain)** | 60% | 90% | 0% | 20% | 비 75% / 낙뢰 OFF | 안개 0.00040, 태양 0.60 |
| **6: 뇌우 (Storm)** | 80% | 100% | 0% | 100% | 비 100% / 낙뢰 ON | 안개 0.00065, 태양 0.35 |

---

## 4. 변경된 파일 목록 및 역할

- [volumetric_cloud.gdshader](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/shaders/volumetric_cloud.gdshader)
  - `cloud_type`(0~3), `puffiness`, `curl_factor` uniform 파라미터 추가.
  - Billow 변환 및 반구형/모루형/새털형 절차적 밀도 함수 구축.
- [cloud_cluster_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/weather/cloud_cluster_manager.gd)
  - 적운 10개, 층적운 8개, 권운 8개, 적란운 4개를 고도별로 사전 배치.
  - `configure_composition()` 메서드를 통해 기상별 활성화 비율 및 색상 동적 제어.
- [weather_manager.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/weather/weather_manager.gd)
  - 7대 기상 상태 머신 확장 및 고도별 구름 합성 지휘.
- [pause_settings_view.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/views/pause_settings_view.gd)
  - 환경 설정 창 날씨 드롭다운 옵션을 7개 기상 상태로 확장.
- [pause_settings_controller.gd](file:///c:/Users/khw/Desktop/가상현실%20렌더링/godot_project/scripts/controllers/pause_settings_controller.gd)
  - 확장된 7개 기상 상태 인덱스 연동 및 로깅 동기화.
