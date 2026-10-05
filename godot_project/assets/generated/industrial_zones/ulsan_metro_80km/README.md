# 울산 절차 공단 배치 데이터
울산 본항·온산항 주변의 게임용 육지 후보를 사용한다. 실제 공단 경계나 실제 시설 배치를 재현한 자료가 아니다.

- `zone_ids.png`: 16bit 구역 ID. 0은 구역 밖이다.
- `excluded_water.png`: 수계와 해안 이격 제외 마스크.
- `allowed.png`: 확정 구역에서 수계·경사·기존 시설·도로를 제외한 설비 후보 영역.
- `excluded_all.png`: 허용 마스크의 반전. 도로 생성은 별도의 도로 안전 영역을 사용한다.
- `regions.json`: 구역 상태와 경계 원본 해시.
- `roads.json`: 내부 도로 중심선·폭과 기존 도로 접속점.
- `parcels.json`: 필지 경계.
- `placements.json`: 설비·기초·진입로·부착 배관·조명 참조와 표시 거리 설정.
- `layout_preview.png`: 흑백 배치도. 기존 건물과 기존 도로의 상세 모델은 표시하지 않는다.
- `manifest.json`: 산출물 SHA256·지도 bbox·배치 고도 범위·해상도.

경계는 `config/industrial_zones.geojson`, 규칙은 `config/industrial_zones.json`에서 관리한다. 기존 경계가 있으면 해당 경계를 사용한다. 자동 후보 지정은 경계 목록이 비어 있고 자동 지정 설정이 켜져 있을 때만 수행한다.

프로젝트 루트에서 명시적 가상환경으로 배치와 색인을 차례로 갱신한다.

```powershell
& '.\.venv_campus\Scripts\python.exe' pipeline/processors/industrial_zones/build_sites.py
& '.\.venv_campus\Scripts\python.exe' pipeline/indexer/build_asset_index.py
```

마스크 생성기만 실행하면 기존 시설을 고려한 배치 결과까지 갱신되지 않는다. 배치 변경에는 `build_sites.py`를 사용한다. 게임에서는 울산 80km 맵의 설정에서 `절차 생성 공단 표시`를 켜거나 끌 수 있다.
