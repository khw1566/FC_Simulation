# 울산 댐 공개 자료 조사 기록
조사일: 2026-10-11. 원본 지도·수역·DEM은 읽기 전용으로 사용했다.

- 시설 제원: `config/ulsan_dams.json`의 공식 출처 URL 및 채택 근거 참조.
- 공개 댐 형상: `osm_dams.json`, Overpass `https://overpass.kumi.systems/api/interpreter`, 조회식 `[out:json][timeout:35];way[waterway=dam](35.38,129.0,35.75,129.4);out tags geom;`.
- OSM 자료: OpenStreetMap contributors, ODbL-1.0. 수역은 기존 `godot_project/assets/maps/ulsan_metro_80km/hydro/lake.geojson`, 도로는 기존 `data/raw/ulsan_metro_80km/highways/full_80km.json`을 읽었다.
- 항공영상: Esri World Imagery MapServer 공개 export. 서비스 원본 메타데이터는 `imagery_service.json`에 보관했다. 출처: Esri, Vantor, Earthstar Geographics, and the GIS User Community. 촬영 날짜는 확인하지 못했으므로 현재 공사 상태를 판정하는 근거로 사용하지 않았다. 영상은 조사 증거이며 생성 모델의 텍스처에 사용하지 않았다.
- `daeam_crest_imagery.png`: bbox `129.180,35.540,129.188,35.548`, bboxSR/imageSR 4326, 1000×1000. 북동단 본댐 축선과 OSM 관리도로 1389839978을 대조했다.
- `daeam_imagery.png`와 `crest_road_candidates.json`의 서남단 도로는 배치에서 제외한 초기 후보다. 항공영상으로 유입부임을 확인했다. 활성 축선은 설정 JSON과 생성 카탈로그에만 기록한다.
- 선암댐은 OSM 산책로 469846115의 직선 부분과 항공영상의 제방 마루를 대조했다. 공식 길이 차이를 맞추기 위한 임의 연장은 하지 않았다.
- 사연댐의 OSM 469893650은 별도 여수로 구역이다. 본댐 166906642와 구분했다. 회야댐도 본댐 156415883과 서남측 여수로 156415884를 구분했다.
- 여수로·취수탑·수문·관리동의 상세 제원은 미조사로 이번 생성 범위에서 제외했다. 회야댐의 2026년 수문 사업 발표를 완공 시설로 해석하지 않았다.
