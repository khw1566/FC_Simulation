# 태화강 토목시설 및 투명 수면 작업 결과

2026-10-11. 울산 80km 지도에 연결한 조사 기반 경량 모델과 수면 표현이다. 전체 지도 실행은 하지 않았다.

## 적용 결과

- 반천 부근 보·어도, 여천 유수지 호안, 여천 배수문 3곳을 좌표에 연결했다.
- 배수 암거·토출구와 20m 사석 호안·관리로는 재사용 모듈로 만들었다. 미확인 위치에 자동 배치하지 않는다.
- 태화강 조사 중심선 약 30.62km 구간에 별도 수면·하상·강변 씬 101개를 연결했다. 하류의 해양 마스크 분류 구간도 포함한다.
- 수면은 깊이 버퍼와 하상 속성을 사용하는 투명 PBR 셰이더다. 수심 감쇠, Fresnel 반사, 하류 방향 UV 잔물결, 얕은 기슭과 보 하류 포말을 적용했다.
- 수면을 불투명한 지형 물색에서 분리했다. 자갈 하상은 수면 아래에서 비치며, 유수지는 느린 공간 잔물결을 사용한다.
- 원본 DEM 파일을 보존하고 실행 중 이미지 복사본에만 국소 패치를 적용한다. 기존 지형 충돌도 수정된 복사본을 사용하며 정밀 하상에 별도 삼각형 충돌을 둔다.
- 강변 18m 이내에 경사면을 연결한다. 지형 제거 마스크는 경사면보다 보수적으로 좁히고 바다 평면에도 같은 제외 영역을 전달한다.

## 시설과 근거

| 시설 | 삼각형 수 | 연결 상태 |
|---|---:|---|
| 반천 부근 보와 어도 | 160 | 지도 배치 |
| 여천 유수지 호안 | 304 | 지도 배치 |
| 여천 유수지 배수문 | 564 | 지도 배치 |
| 배수 암거·토출구 모듈 | 300 | 모듈만 생성, 미배치 |
| 사석 호안·관리로 모듈 | 86 | 모듈만 생성, 미배치 |

- 보 축선: [OSM way 1540924116](https://www.openstreetmap.org/way/1540924116). 프로젝트 지도 좌표에서 약 101.68m다. 공식 보 명칭은 미확인이므로 ‘반천 부근’은 위치 설명용 이름이다. 콘크리트 단면·어도 치수는 영상 기반 추정이다.
- 유수지 수역: [OSM way 187657447](https://www.openstreetmap.org/way/187657447), [전면 수역 187657448](https://www.openstreetmap.org/way/187657448). 공개 경계와 [Esri World Imagery](https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer)를 교차 확인했다. 촬영시점은 미확인이다.
- 여천 시설의 사업 맥락: [울산시 유입수로 공사 현황](https://www.ulsan.go.kr/u/metro/transfer/alimi/normal/view.ulsan?mId=001008008002001000&nttNo=218), [여천 유수지 준설·배수펌프 사업 자료](https://www.ulsan.go.kr/u/rep/bbs/view.do?bbsId=BBS_0000000000000027&dataId=166762&mId=001004003001000000). 공사 중 우수토실을 완공 시설로 생성하지 않았다.
- 현존 시설과 계획을 구분하기 위해 [태화강 하천기본계획 변경 초안](https://www.bukgu.ulsan.kr/download.do?uuid=441a5607-fc3f-4be4-bf75-dd430f083db2.pdf)을 참고했다.
- [보 처리방안 연구보고서](https://www.codil.or.kr/filebank/original/RK/OTKCRK230687/OTKCRK230687.pdf)가 철거 사실을 설명하는 태화강 방사보는 생성하지 않았다. 삼산 유수지의 운동시설 상부를 열린 수역으로 바꾸지 않았다.
- 공개 OSM 보 조회 스냅샷 시각은 2026-07-28이다. 기존 중심선·수역 캐시와 촬영일 미확인 영상은 최신 현장 측량으로 간주하지 않는다. OpenStreetMap contributors / ODbL-1.0. 영상 제공 표기: Esri, Vantor, Earthstar Geographics, GIS User Community.

## 추정 범위

- 하류는 기존 공개 수역 면과 약 14m 격자의 해양 마스크를 사용한다. 상류 약 14.54km는 공개 수역 면이 없어 OSM 중심선에 영상·보 축선 기반 가변 폭을 부여했다. 폭 제어점은 catalog.json의 boundary_status에 보존했다.
- 수면 종단은 DEM 중앙 표본을 완만하게 만들고 하류 역경사를 제거한 시각화 값이다. 보 마루 기준 표고는 약 52.34m이며 측량 표고가 아니다.
- 하천 깊이는 최대 약 2.22m, 유수지 깊이는 약 1.75m의 제작 값이다. 0.65m/s는 물결 위상 이동 속도이며 관측 유속·실제 유량을 의미하지 않는다. 조석과 수문 작동을 계산하지 않는다.
- 배수문은 공개 수역 경계와 영상에서 추정한 축선·외관이다. 실제 문짝 수, 치수, 운전 상태와 일치한다고 보장하지 않는다.
- 화면 굴절, 수중 카메라, 유체·홍수 시뮬레이션은 구현하지 않았다. 투명도·환경 반사·흐름 잔물결에 집중했다.

## 확인한 범위

- 전용 프리뷰에서 Godot 4.3 Compatibility 및 Forward+ 렌더링을 확인했다. 마지막 Forward+ 로그와 실제 Compatibility 구조 검사 로그에 오류가 없다.
- 지도·높이 범위 가드, 복사본 패치, 비대상 픽셀 보존, 3곳 중복 배치 방지, 101개 씬 로딩, 하상 충돌, 바다 중복 수면 제외를 확인했다.
- 물리 레이의 하상 충돌 높이와 생성 하상 높이가 허용 오차 0.5m 안에서 일치했다.
- 같은 카메라의 0초/2초 캡처에서 전체 화면 약 20.42% 픽셀이 변화했다. 성능 수치가 아니라 애니메이션 변화 확인이다.
- 수면 삼각형 6,400개, 하상·강변 15,635개, 시설 5종 1,414개다. 수면 생성 면적 합과 대상 면적의 상대 오차는 0.00000290%다.
- TerrainChunkManager, BuildingRoadManager, KanmonWaterManager는 소스 복사본에서 파싱 검사를 통과했다. 원본 프로젝트 임포터·에디터는 실행하지 않았다.
- 원본 DEM SHA256 유지: c953a6efe1ff426265fc36a9bfb916b7db98e776dc1755d8eb1a2fc69b1a3dc4. 비대상 공통 매니페스트 8,238항목을 보존했다.
- 전체 지도 통행, 다른 품질의 실제 화면, 전체 FPS 및 장시간 실행은 미확인이다. 다른 지도는 기존 표현을 유지한다.
- 셰이더 깊이 변환 근거: [Godot 4.3 깊이 버퍼 문서](https://docs.godotengine.org/en/4.3/tutorials/shaders/advanced_postprocessing.html), [공간 셰이더 문서](https://docs.godotengine.org/en/4.3/tutorials/shaders/shader_reference/spatial_shader.html).

## 산출물과 재생성

- 설정: config/taehwa_civil.json
- 생성기: pipeline/processors/taehwa_civil/
- 에셋: godot_project/assets/generated/taehwa_civil/ (GLB 5개, 시설 씬 5개, 수계 씬 101개, 마스크·패치·카탈로그·매니페스트)
- 프리뷰: results/261011_TaehwaCivilPreview.png
- 구조·수치 결과: results/261011_TaehwaCivilVerification.json
- 격리 경로: previews/taehwa_civil/project 및 integration
- 재생성 순서: 명시적 .venv_campus Python으로 generate.py, 격리 Godot의 bake.gd·fixture.gd·preview.gd, publish.py, 중앙 build_asset_index.py.
- 중앙 색인 결과는 아래에 기록한다. 프리뷰 실행파일은 재빌드하지 않았다.

## 에셋 색인 결과

- 실행: `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py`
- 전체 77,085파일, 태화강 계열 119파일.
- pending 0개. 보류 파일: 없음.
- 태화강 계열 119개 파일의 색인 해시를 실제 파일과 대조했다.
