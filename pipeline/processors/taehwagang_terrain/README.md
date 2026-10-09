# 태화강 둔치 정밀 지형
태화강 국가정원부터 명촌교 부근까지 8km 정사각 영역을 별도 지도 `taehwagang_dunchi`로 생성한다. 기존 울산 광역 지도(COP30 30m)는 수정하지 않는다.
## 실행
프로젝트 루트 PowerShell에서 실행한다. API 키는 환경변수로만 넘기고 저장소에 기록하지 않는다.
```powershell
$env:VWORLD_API_KEY = "<발급 키>"
& 'C:\Users\khw\AppData\Local\Programs\Python\Python312\python.exe' pipeline/processors/taehwagang_terrain/generate.py --dry-run
& 'C:\Users\khw\AppData\Local\Programs\Python\Python312\python.exe' pipeline/processors/taehwagang_terrain/generate.py
```
- `--dry-run`: 키 위치와 VWorld 신규 요청 수만 출력한다.
- `--source auto|vworld|terrarium`: 기본 `auto`는 키가 있으면 VWorld, 없거나 검증 실패 시 Terrarium.
- `--refresh-water`, `--refresh-roads`: 캐시된 Overpass 수계·도로를 다시 받는다.
- `--no-satellite`: VWorld 위성 영상 수집과 확인 이미지의 영상 바탕을 생략한다.
- 환경변수가 없으면 기존 `data/api_keys.json`의 `vworld_api_key`를 사용한다.
## 처리 순서
- 고도 원천: VWorld DEM 노드를 `data/raw/taehwagang_dunchi/vworld_dem/<level>/`에 캐시한다. 노드 행 방향은 Terrarium과의 상관계수로 확정하고 결측은 Terrarium으로 채운다.
- 수계: Overpass 수면 다각형(`water=river`, `waterway=riverbank`)을 본류로, 그 외 수면과 지류를 기타 수면으로 분리한다.
- 하상: 본류 안쪽은 수위 프로파일에서 `bank_slope_run_per_rise` 경사로 `bed_max_depth_m`까지 낮춘다.
- 둔치: 본류에서 출발해 수위 + `max_rise_m` 이하로만 이어지는 연결 영역을 둔치로 보고 `smoothing_sigma_m`로 평탄화한다. 제방이 연결을 끊으므로 제방 뒤 시가지는 정형하지 않는다.
- 강변도로 단면: OSM 도로 중 본류와 나란한 구간(`roads`)을 강변도로로 고른다. 둔치는 수위 + `dunchi_rise_m`의 일정 높이, 강변도로와 그 바깥 시가지는 수위 + `road_rise_m`로 평탄화하고, 도로 가장자리에서 `slope_width_m` 띠에만 S자 곡면 경사를 둔다. 도로보다 `hill_threshold_m` 이상 높은 산지는 원 지형을 유지한다. 강변도로가 없는 구간은 앞 단계 둔치 정형을 유지한다.
- 위성 확인: `results/dunchi_check/`에 위성 영상 위로 수면(파랑), 강변도로(빨강), 기타 도로(회색), 제방 경사(주황), 배치 가능 둔치(초록)를 겹친 이미지를 쓴다. 어긋난 도로는 `roads.include_osm_ids`, `exclude_osm_ids`, `manual_lines`로 보정한다.
- 배치 부지: `placement_pads`의 다각형을 지정 높이 또는 중앙값으로 평탄화한다.
## 산출물
- `godot_project/assets/maps/taehwagang_dunchi/dunchi_heightmap_16bit.png`: 4096px, 약 1.95m 간격, -10m~250m 인코딩.
- `dunchi_watermask_8bit.png`: 255 수면.
- `dunchi_placement_mask_8bit.png`: 255 평탄 둔치(에셋 배치 가능 후보).
- `dunchi_satellite.jpg`: 지도 격자에 정합한 VWorld 위성 영상(배치 참고용).
- `map_meta.json`, `manifest.json`: 해시, bbox, 고도 최소/최대, 해상도, 고도 원천, 정형 통계.
- `maps_registry.json`에 지도가 없으면 추가한다.
## 에셋 배치
- `godot_project/assets/maps/taehwagang_dunchi/placements.json`에 씬 경로와 `lonlat` 또는 `world_xz`를 기록하면 `RiversideAssetPlacer`가 지형 높이에 맞춰 배치한다.
- 고정 높이가 필요한 시설은 `placement_pads`에 부지를 추가해 지형을 먼저 평탄화한 뒤 배치한다.
## 주의
- 수위 프로파일은 추정값이다. 실측 수위 자료로 교체한다.
- VWorld XDServer DEM 엔드포인트 형식이 바뀌면 설정의 `url_template`만 수정한다.
- 생성 후 `pipeline/indexer/build_asset_index.py`를 수동 실행해 에셋 색인을 갱신한다.
