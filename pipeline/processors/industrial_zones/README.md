# 공단 구역 파이프라인
경계 편집과 마스킹에서 시작해 기존 도로에 연결되는 공단을 생성한다. 자동 후보는 사용자가 승인한 게임용 구역이며 실제 공단 경계로 취급하지 않는다.

- `build_masks.py`: 수동 경계의 16bit ID와 수계 제외 마스크.
- `site_inputs.py`: 지형·경사·수계·기존 건물과 도로·철도·문화재·공항 보호 영역.
- `road_graph.py`: 안전 영역 안의 연결 도로망과 기존 도로 접속.
- `parcel_builder.py`: 도로와 진입 여유를 고려한 필지 분할.
- `asset_placer.py`: 전체 footprint와 기초 고저 차, 진입 공간을 검사하는 프로필별 설비 배치.
- `build_sites.py`: 후보 선정·전체 생성·배치도·매니페스트 발행.

`config/industrial_zones.geojson`의 확정 구역을 입력으로 사용한다. 처음 경계가 비어 있을 때만 설정에 따라 울산 본항·온산항 주변 후보를 자동 선정한다. 필수 지형·지도·시설 데이터가 없거나 도로 연결이 불가능하면 생성 실패를 보고한다.

```powershell
& '.\.venv_campus\Scripts\python.exe' pipeline/processors/industrial_zones/build_sites.py
& '.\.venv_campus\Scripts\python.exe' pipeline/indexer/build_asset_index.py
```

산출물은 `godot_project/assets/generated/industrial_zones/ulsan_metro_80km`에 기록한다. 원본 산업 모델은 변경하지 않는다. 마스크만 갱신할 때와 배치를 갱신할 때의 차이는 산출물 README를 참고한다.
