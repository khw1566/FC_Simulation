# 260921_BuildingFootprintSvgReport.md
작성 일자: 2026-09-21
작성자: Antigravity AI 시스템 엔지니어

## 1. 개요 및 목적
본 문서는 간몬 해협 가상 지형 렌더링 프로젝트에서 OSM 실측 건물 데이터(3,364동)의 밑면 다각형(Footprint Polygon)을 고해상도 2D 벡터 SVG(Scalable Vector Graphics) 파일로 추출하고, 각 건물에 고유 넘버링을 부여하여 24-bit RGB 색상 인코딩으로 매핑한 데이터 구성 내역을 기록한 엔지니어링 리포트입니다.

## 2. 좌표 변환 및 지리 정합 규격
- **캔버스 해상도:** 4096 x 4096 (지형 16-bit 높이맵 및 위성 스플랫맵과 1:1 지리 정합)
- **지리 바운딩 박스 (BBox):**
  - South: 33.8000, North: 34.0500 (위도 폭 0.25도, 약 27.75km)
  - West: 130.8000, East: 131.1000 (경도 폭 0.30도, 약 27.60km)
- **픽셀 좌표 변환 수식:**
  - $X = \frac{lon - 130.8000}{131.1000 - 130.8000} \times 4096$
  - $Y = \frac{34.0500 - lat}{34.0500 - 33.8000} \times 4096$

## 3. 건물 넘버링 및 색상 인코딩 설계
각 건물 다각형은 고유 식별 정수 ID($1 \le N \le 3,364$)를 부여받으며, 셰이더, 이미지 프로세서 및 향후 절차적 지형 빌더에서 픽셀 색상만으로 즉시 무손실 디코딩할 수 있도록 24-bit RGB 색상 코드로 인코딩되었습니다.
- **인코딩 수식:**
  - $R = (N \gg 16) \& \text{0xFF}$
  - $G = (N \gg 8) \& \text{0xFF}$
  - $B = N \& \text{0xFF}$
  - Hex 색상 표기: `#RRGGBB`
- **배경 처리:**
  - 건물이 존재하지 않는 무효 배경 영역은 검정색(`fill="#000000"`, $ID=0$)으로 설정되었습니다.
- **SVG 요소 구조:**
  - 각 다각형(`<polygon>`)은 `id`, `data-building-number`, `data-levels`, `data-height`, `data-name`, `fill`, `points` 속성을 모두 포함하여 벡터 및 메타데이터 동시 활용이 가능합니다.

## 4. 산출물 및 자산 인덱스
- **SVG 벡터 파일:** `godot_project/assets/generated/building_footprints.svg` (899,376 바이트, 3,364개 건물 다각형)
- **건물 인덱스 메타데이터:** `godot_project/assets/generated/building_footprints_index.json` (722,338 바이트, 전체 건물 번호-색상-층수 매핑)
- **자산 매니페스트 갱신:** `godot_project/assets/generated/manifest.json`에 SHA-256 해시 및 파일 규격 등록 완료
- **신규 프로세서 모듈:** `pipeline/processors/building_svg_processor.py` 및 `pipeline/processors/__init__.py` 등록 완료
