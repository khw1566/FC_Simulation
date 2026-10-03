# 260926_RealisticRiverWidthScalingReport.md
작성일자: 2026년 09월 26일
작성자: Antigravity AI Agent

## 1. 개요 및 문제 진단
대형 맵(`ulsan_metro_60km`, `southeast_mega_140km`)에서 하천(강)의 폭이 실제 지형에 비해 과도하게 넓게(수백 미터에서 1km 이상) 렌더링되던 문제를 진단하고 실제 물리적 하천 폭에 맞추어 스케일링되도록 전처리 파이프라인 및 자산을 갱신했습니다.

### 발생 원인
- `pipeline/processors/watermask_processor.py`에서 OSM 하천 중심선(`waterway=river`, `waterway`) 렌더링 시 해상도 및 맵 축척과 무관하게 32픽셀 고정 두께(`thickness=32`)로 라인을 래스터화하고 있었습니다.
- 5km 정밀 맵(`ulsan_uc_west`, 2048px, 1px당 약 2.44m)에서는 32px이 약 78m에 해당하여 자연스러웠으나,
- 60km 광역 맵(`ulsan_metro_60km`, 4096px, 1px당 14.65m)에서는 32px이 **약 468.8m**로 과장되었고,
- 140km 메가리전 맵(`southeast_mega_140km`, 4096px, 1px당 34.18m)에서는 32px이 **약 1,093.8m(1km 초과)**로 극단적인 왜곡이 발생했습니다.

---

## 2. 해결 방안 및 물리적 스케일링 공식

### 픽셀당 미터 해상도 기반 동적 두께 계산
```python
world_size_m = float(self.config.get("world_size_meters", self.config.get("area_km", 28.0) * 1000.0))
m_per_px = world_size_m / max(target_w, 1)

# 실제 강폭(본류 60m, 소하천 20m, 해안선 경계 15m)을 해상도로 나눈 픽셀 수 적용
river_px = max(1, int(round(60.0 / m_per_px)))
waterway_px = max(1, int(round(20.0 / m_per_px)))
coastline_px = max(1, int(round(15.0 / m_per_px)))
```

### 각 맵별 적용 결과 비교
- `ulsan_uc_west` (5km, 2048px):
  - 1px = 2.44m $\rightarrow$ 강폭 60m 기준 **25 px** (자연스러운 60m 하천 폭 유지)
- `ulsan_metro_60km` (60km, 4096px):
  - 1px = 14.65m $\rightarrow$ 기존 32px(468m)에서 **4 px(약 58.6m)**로 정상 축소 (약 87.5% 폭 축소)
- `southeast_mega_140km` (140km, 4096px):
  - 1px = 34.18m $\rightarrow$ 기존 32px(1,093m)에서 **2 px(약 68.4m)**로 정상 축소 (약 93.7% 폭 축소)
- 태화강 하류 등 실제 폭이 100~300m인 구간은 OSM Relation 멀티폴리곤(`fillPoly`)으로 실측 경계선 그대로 정확하게 마스킹됩니다.

---

## 3. 갱신된 파일 및 결과 자산
- [watermask_processor.py](file:///c:/Users/work/Desktop/가상현실%20렌더링/pipeline/processors/watermask_processor.py): 물리적 거리 기반 동적 두께 계산 로직 적용.
- [ulsan_metro_60km_watermask_8bit.png](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_metro_60km/ulsan_metro_60km_watermask_8bit.png): 4096 해상도 재생성 완료.
- [southeast_mega_140km_watermask_8bit.png](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/southeast_mega_140km/southeast_mega_140km_watermask_8bit.png): 4096 해상도 재생성 완료.
- [ulsan_watermask_8bit.png](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_uc_west/ulsan_watermask_8bit.png): 2048 해상도 재생성 완료.
- [manifest.json (ulsan_metro_60km)](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/ulsan_metro_60km/manifest.json) 및 [manifest.json (southeast_mega_140km)](file:///c:/Users/work/Desktop/가상현실%20렌더링/godot_project/assets/maps/southeast_mega_140km/manifest.json): SHA-256 해시 인덱싱 갱신 완료.
- Godot 4 엔진 구문 및 리소스 검사 통과 (`check-only` 결과 이상 없음).
