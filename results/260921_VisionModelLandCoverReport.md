# 260921_VisionModelLandCoverReport.md
날짜: 2026-09-21
작성자: Antigravity AI Engineering Team

## 1. 개요 및 배경
- 위성 및 항공 원격탐사 영상은 산악 음영, 계절별 식생 변화, 건물의 그림자, 도심지 인공 구조물 간 반사율 차이 등으로 인해 단순 RGB 색상 임계치 기반 분류 시 심각한 오분류가 발생합니다.
- 복잡한 텍스처, 공간적 형상(패턴), 전역 맥락(Context)을 이해하여 농경지(논, 밭), 도회지, 산림, 하천 수변구역을 정밀 분할하기 위해 Hugging Face 생태계에서 검증된 최신 비전 파운데이션 모델을 조사 및 분석하였습니다.

## 2. Hugging Face 추천 비전 모델 비교 분석

| 모델명 | 아키텍처 및 규모 | 사전 학습 데이터셋 | 주요 분류 클래스 및 강점 | 본 프로젝트 적합도 |
| :--- | :--- | :--- | :--- | :--- |
| **SegFormer (OpenEarthMap fine-tuned)**<br>(`odil111/segformer-fine-tuned-on-openearthmap` 등) | Hierarchical Vision Transformer (B0~B5) | OpenEarthMap (전 세계 고해상도 위성/항공 RGB 8개 클래스) | 농경지(Agriculture), 산림(Forest), 도회지(Urban/Building), 나지(Bareland), 수계(Water), 도로(Road) 즉시 출력 가능 | **최상 (즉시 적용 권장)**<br>- 추가 학습 없이 RGB 위성 이미지에 대해 바로 제로샷/추론 가능<br>- 경량 및 고속 추론 |
| **Prithvi-EO-1.0-100M**<br>(`ibm-nasa-geospatial/Prithvi-EO-1.0-100M`) | Temporal Vision Transformer (IBM-NASA 협업) | NASA Harmonized Landsat Sentinel-2 (HLS 다중분광/시계열) | 토지 피복 분류, 작물 유형(Crop-type) 식별, 홍수/수역 탐지 | **상 (다중분광 처리 시 최적)**<br>- NASA 공식 지구관측 기반 모델로 정밀도 우수<br>- 파이프라인 파인튜닝 시 최고 성능 |
| **SAM-HQ (Segment Anything in High Quality)**<br>(`SysCV/sam-hq`) | Vision Transformer with High-Quality Output Token | SA-1B + 정밀 원격탐사 마스크 | 미세한 강폭 경계, 수변 완충구역(Riparian), 논두렁/경작지 구획선의 날카로운 경계선 추출 | **상 (수변구역/경계선 정밀화)**<br>- 복잡한 하천 만곡부 및 강변 자갈밭 마스킹에 탁월 |
| **SkySense / DOFA** | 멀티모달 대규모 원격탐사 파운데이션 모델 | 수십억 개 단위 EO 다중 스펙트럼 데이터 | 다양한 해상도 및 다중 모달리티 범용 해석 | **중 (고성능 클러스터용)**<br>- 모델 크기가 커 로컬 단일 파이프라인에는 다소 무거움 |

## 3. 권장 구현 파이프라인 아키텍처

```
[ 위성 타일 RGB 영상 (GSI / Sentinel-2) ]
                   │
                   ▼
┌────────────────────────────────────────────────────────┐
│ 1단계: SegFormer (OpenEarthMap) 시맨틱 분할 추론 엔진   │
│ - 산악/산림(Forest) 마스크 분리                       │
│ - 농경지/논밭(Agriculture/Field) 마스크 분리           │
│ - 도회지/아스팔트(Urban/Paved) 마스크 분리              │
└────────────────────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────┐
│ 2단계: SAM-HQ 기반 하천 수변구역(Riparian Zone) 정합  │
│ - 하천 경계선(Riverbank) 및 조간대 수변 버퍼 마스크 분리│
└────────────────────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────┐
│ 3단계: RGBA 4채널 스플랫맵 래스터화                     │
│ (R: 산림, G: 농경지, B: 도회지, A: 하천/수변)          │
└────────────────────────────────────────────────────────┘
```

## 4. 결론 및 추진 전략
- **1순위 도입:** Hugging Face의 `odil111/segformer-fine-tuned-on-openearthmap` 또는 `nave1616/SegFormer-landcover-FT`를 파이프라인의 `landcover_processor.py`에 PyTorch/Transformers 파이프라인으로 연결하여 농경지/산림/도회지를 1차 분리합니다.
- **2순위 보강:** 정밀 강폭 및 수변구역 식별에는 `SAM-HQ` 또는 OSM의 `waterway=riverbank` 폴리곤을 융합하여 마스크 경계 품질을 극대화합니다.
