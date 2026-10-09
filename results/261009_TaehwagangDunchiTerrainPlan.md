# 태화강 둔치 별도 지형 구현 계획 및 방식 비교
- 작성일: 2026-10-09
- 대상: 태화강 국가정원~명촌교 둔치, 8km 정사각 별도 지도 `taehwagang_dunchi`
## 현황
- 울산 지도는 OpenTopography COP30(30m)을 4096px로 늘린 높이맵을 사용한다. 30m 원본에서는 둔치(폭 50~200m)와 제방이 몇 픽셀로 뭉개진다.
- 기존 보정(`tools/apply_taehwa_river_integration.py`)은 수면 마스크로 하상만 평탄화하며 둔치 단면은 다루지 않는다.
## 방식 비교
- A. API 키 고도(VWorld 3D 지형 DEM): 국내 수치표고 기반, 노드 표본 간격 약 3m(level 14). 키 필요, 일일 요청 한도 관리 필요, 행 방향 문서 부족.
- B. OpenTopography 키: COP30/SRTM 등 전역 30m 자료만 제공하여 현재 품질과 같다. 개선 효과 없음.
- C. 공개 Terrarium 타일(키 불필요): 국내는 SRTM 계열 30m급, 하천 주변 오차가 크다. 대체·검증 기준으로만 적합.
- D. 국토정보플랫폼 수치표고모델 5m 파일: 품질 우수하나 수동 내려받기와 좌표계(EPSG:5186) 변환이 필요하다.
- E. 수계 기반 둔치 정형(절차 생성): 원천 고도와 무관하게 하상·둔치·제방 경계를 평탄 단면으로 만든다. 에셋 배치 표면이 일정해진다.
## 선택
- A + E 조합을 기본으로 한다. 지형 형태는 VWorld DEM에서, 둔치 평탄면과 하상 단면은 OSM 수계 기반 정형에서 얻는다.
- 키가 없거나 VWorld 검증(상관계수 0.6 미만)이 실패하면 C + E로 자동 대체하여 파이프라인이 멈추지 않는다.
- D는 VWorld 결과가 부족할 때 같은 `TerrainGrid.resample` 입력으로 추가할 수 있다.
## 구현 내용
- 설정: `config/taehwagang_dunchi_terrain.json`
- 수집: `pipeline/collectors/riverside_sources/`
- 처리: `pipeline/processors/taehwagang_terrain/` (실행법은 같은 폴더 README)
- Godot: `scripts/terrain/riverside_asset_placer.gd`, `main_world.tscn`의 `RiversideAssetPlacer` 노드, `assets/maps/taehwagang_dunchi/placements.json`
- 지도 등록: 생성기가 높이맵을 만든 뒤에만 `maps_registry.json`에 추가한다. 생성 전에는 지도 목록에 나타나지 않는다.
## 검증
- 클라우드 환경에서 VWorld와 Overpass 접속이 차단되어 실제 산출물은 생성하지 않았다.
- 512px 축소 격자, Terrarium zoom 13, 합성 하천으로 수집-정형-부지 평탄화 경로를 확인했다.
- 16bit PNG, 마스크, map_meta, 매니페스트, 지도 목록 등록을 임시 경로에서 확인했다.
- Godot 실행 검증은 하지 않았다.
## 남은 작업
- 사용자 PC에서 VWorld 키로 생성 실행 후 산출물 커밋, 에셋 색인 갱신
- 실측 수위 자료로 `water_level_profile` 보정
- 코덱스 제작 에셋 배치 시 `placement_pads`와 `placements.json` 작성
