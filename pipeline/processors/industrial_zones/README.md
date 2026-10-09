# 공단 구역 파이프라인
OSM 산업·항만 용지 경계를 공단 구역으로 사용하고, 도로로 나눈 블록마다 용도를 정해 설비를 채운다. 내부 시설 배치는 게임용 절차 생성이며 실제 공정 배치를 재현하지 않는다.

- `landuse_zones.py`: OSM 산업 용지를 60m 간격까지 합쳐 공단 구역으로 만들고 0.4km² 미만은 제외.
- `site_inputs.py`: 지형·경사·수계·도로·철도·문화재·공항 보호 영역과 기존 건물(대체 대상) 목록.
- `block_divider.py`: 기존 도로를 1차 경계로, 큰 블록은 긴 축에 수직인 새 도로로 재귀 분할. 떨어진 도로 묶음은 기존 도로에 접속.
- `block_signals.py`: 블록 안 기존 건물의 원형 비율·크기·이름에서 용도 단서 추출.
- `district_planner.py`: 저장고·공정·공장·조선소·물류·지원 시설 용도 지정. 저장고 옆 블록은 공정 구역으로 묶음.
- `district_fillers.py`: 용도별 단계 배치. 블록 방향 좌표계에서 대형 설비를 먼저 채우고 남은 틈을 작은 설비로 채움.
- `district_links.py`: 저장고-공정 사이 파이프랙, 지원 시설 사이 송전탑 선로.
- `asset_catalog.py`: 산업·플랜트 카탈로그 통합과 footprint·랙 부착 보강.
- `build_masks.py`: 구역 ID와 수계 제외 마스크.
- `build_sites.py`: 전체 생성·배치도·매니페스트·건물 대체 영역 발행.

```powershell
& 'C:\Users\khw\AppData\Local\Programs\Python\Python312\python.exe' pipeline/collectors/industrial_landuse_collector.py
& '.\.venv_campus\Scripts\python.exe' pipeline/processors/industrial_zones/build_sites.py
& '.\.venv_campus\Scripts\python.exe' pipeline/indexer/build_asset_index.py
```

수집기는 `data/raw/ulsan_metro_80km/industrial/landuse_industrial.json`이 있으면 다시 받지 않는다(`--refresh`로 갱신). `build_sites.py`는 경계 파일이 아직 OSM 변환본이 아닐 때만 수집 자료로 `config/industrial_zones.geojson`을 만든다. 이후에는 경계 편집기(`previews/industrial_zone_editor/editor.html`)에서 고친 경계를 그대로 쓰며, OSM 기준으로 다시 만들려면 `--rebuild-zones`를 붙인다. 산출물은 `godot_project/assets/generated/industrial_zones/ulsan_metro_80km`에 기록하며 `building_suppression.json`은 게임에서 구역 안 범용 건물을 생성하지 않는 데 쓴다.
