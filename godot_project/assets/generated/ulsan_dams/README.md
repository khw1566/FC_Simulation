# 울산 용수댐 경량 모델과 배치
사연·대곡·대암·선암·회야댐 5종. 공식 길이·높이, 공개 축선, 추정 단면을 구분한 시각화 모델입니다.

- 근경·원경 GLB 10개, 충돌 및 거리 LOD를 포함하는 자체 완결 TSCN 5개.
- 원점은 댐마루 중앙, Y 위, -Z 저수지측, 미터 단위.
- 마루 폭 6m, 사면비 상류 1:2 / 하류 1:2.2, 난간은 시각화용 추정입니다.
- 대암·선암 축선은 공개 도로·산책로와 저수지 경계로 추정했습니다. 나머지 3곳은 공개 OSM 댐 축선을 사용합니다.
- 지도상 축선 길이를 보존하므로 공식 제원 길이와 차이가 나는 경우 X 방향으로 맞춥니다.
- 댐마루 표고는 현재 지도 DEM의 내부 17개 표본 90백분위 + 0.35m이며 측량 표고가 아닙니다.
- 미조사 여수로·취수탑·관리동·수문과 미래 공사는 생략했습니다. 기존 수역·DEM을 수정하지 않습니다.
- DEM에 이미 포함된 제방을 이중으로 올리지 않도록 상부·사면을 지표 +0.45m 이상에 맞추고 충돌도 갱신합니다. 양 끝 사면 폭은 시각화용으로 줄입니다.
- 근경 3.5km / 원경 24km 거리 소거. 충돌은 근경 메시 기준이며 실제 지도 통행은 미확인입니다.
- BuildingRoadManager에서 지도 범위가 포함하는 댐을 배치합니다. 실행 중 생성·색인은 하지 않습니다.
- 재생성: `.venv_campus/Scripts/python.exe pipeline/processors/ulsan_dams/generate.py` 후 전용 Godot 프로젝트의 `bake.gd`, `fixture.gd`, `publish.py`, 중앙 색인 순서. Godot 사용자 경로도 previews/ulsan_dams 안으로 지정합니다.
- 조사 근거: `config/ulsan_dams.json`, `results/261011_UlsanDamsReport.md`. OSM: OpenStreetMap contributors / ODbL-1.0.
