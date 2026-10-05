# 실제 광역 고도 원경
가까운 지도 영역은 기존 상세 지형을 유지하고, 외곽은 공개 Terrain Tiles 표고로 표시한다. 건물·도로·충돌은 이 계열의 역할이 아니다.

- 카탈로그: `terrain.json`, 지도 좌표와 광역 Web Mercator bbox, 해상도, 출처 기록.
- 고도: `regional_height.f32`, little-endian float32 미터, 행 우선 4096 × 4096.
- GPU 고도: `regional_height_rgb.png`, 정규화 R × 65280 + G × 255 − 32768 미터. 색상 텍스처가 아니므로 source_color로 해석하지 않는다.
- 상세 경계 아틀라스: 지도별 513 × 513. 활성 높이맵에서 표본화한다.
- 광역 자료는 zoom 8 공개 타일을 재표본화했다. 약 600m 표본 간격이며 30m 정밀 지형 또는 실제 지표 피복을 의미하지 않는다.
- 곡률은 상세 영역 밖에서 완만하게 적용하는 시각 근사다. 현재 지도의 위경도→평면 변환을 유지하며 구면 비행 좌표계를 변경하지 않는다.
- 생성: `.venv_campus/Scripts/python.exe pipeline/processors/build_horizon_terrain.py`.
- 에셋 색인: `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py`.

## 출처
Terrain Tiles: Mapzen/Tilezen. SRTM and GMTED2010 terrain data courtesy of the U.S. Geological Survey. Global ETOPO1 terrain data: U.S. National Oceanic and Atmospheric Administration, DOC/NOAA/NESDIS/NCEI.

- https://registry.opendata.aws/terrain-tiles/
- https://github.com/tilezen/joerd/blob/master/docs/formats.md
- https://github.com/tilezen/joerd/blob/master/docs/attribution.md

기존 근거리 DEM과 이 공개 타일은 출처·수집 시점·수평 표본 간격이 다르다. 6km 높이 연결과 18km 색상 연결은 경계의 시각적 차이를 완화한다. 모든 외곽 도시에 대한 실제 피복 자료는 추가하지 않았다.
