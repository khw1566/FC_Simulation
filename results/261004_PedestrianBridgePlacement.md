# 새 교량 에셋 확인 및 월드 배치

제작된 원본 SCN 3종을 확인하고 선바위교와 굴화리–다운동 징검다리를 기존 교량 로딩 경로에 연결했다. 범용 보행 육교는 사용자 요청에 따라 배치하지 않고 보관한다. 원본 모델 파일은 변경하지 않았다.

## 배치 결과

| 에셋 | 위치 및 연결 선형 | 월드 길이 | 배치 범위 |
|---|---|---|---|
| 선바위교 | OSM 153128115, 중심 약 35.578073°N / 129.235346°E | 약 159.31m | 울산 80km, 동남권 140km |
| 굴화리–다운동 징검다리 | OSM 보행로 472077914의 중앙 횡단 구간, 중심 약 35.558550°N / 129.264871°E | 약 172.39m | 울산 80km, 동남권 140km, 서부캠퍼스 5km |
| 범용 보행 육교 | 사용자 지정: 보관만 함 | 원본 유지 | 배치 없음 |

선바위교의 원본 160m 모델은 지도 길이에 거의 동일하게 맞춘다. 징검다리는 원본 길이 100m와 선택한 OSM 횡단 구간 길이에 차이가 있어 진행 방향 길이만 약 1.724배 조정한다. 폭과 높이 치수는 유지한다. 징검다리 위치는 [보도된 다운동–굴화 연결 시설](https://www.iusm.co.kr/news/articleView.html?idxno=1027634)과 인접 보행로를 대조한 근사 배치이며 측량으로 확인된 양끝점은 아니다.

## 지형 접속과 중복 처리

- 원본 에셋의 RoadA/RoadB 및 BankA/BankB 기준점을 지도 좌표에 정렬했다. 원본 모델에 있는 보행면 충돌을 유지했다.
- DEM을 양끝과 상판 너비에 걸쳐 샘플링하여 모델의 기울기와 표고를 맞춘다. 울산 80km의 선바위교는 상판 지형 관통을 피하기 위해 약 3.27m 추가 상승 보정이 적용된다.
- 선바위교 양안에는 약 40m 접속 램프를 추가하고 교각 기초를 필요한 경우 지형까지 연장한다.
- 징검다리를 대체할 때 전체 원본 보행로를 없애는 대신 양쪽 진입 구간을 별도 보행면으로 복원한다. 원본 보행로의 tunnel=yes 표시는 저상 지상 횡단 시설 표현에 적용하지 않는다.
- 두 시설의 원본 OSM 도로는 기존 중복 제거 경로에서 제외한다. 주변 건물과 모든 인접 도로를 재구성하는 작업은 하지 않았다.

## 파일 및 재생성

- 배치 카탈로그: `godot_project/assets/generated/pedestrian_bridges/placements.json`
- 배치 모듈: `godot_project/scripts/terrain/pedestrian_bridge_placement.gd`
- 기존 교량 관리자: `godot_project/scripts/terrain/bridge_landmark_manager.gd`
- 생성기: `pipeline/processors/build_pedestrian_bridge_placements.py`

프로젝트 루트에서 아래 명령으로 확보된 원본 지도 자료의 배치 카탈로그와 자산 매니페스트를 재생성한다.

```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/build_pedestrian_bridge_placements.py
```

## 검증

4개 지도 메타데이터와 원본 높이맵 샘플만 사용한 경량 검증에서 총 5개 배치 인스턴스를 확인했다. 일본 지도에는 배치되지 않으며, 서부캠퍼스 지도에는 범위에 포함된 징검다리만 배치된다. 기준점 위치 오차 1cm 이내, 좌우 반전 없음, 충돌 보존, 중복 제거와 징검다리 진입로 존재 검사를 통과했다.

전체 월드·건물·지도 청크를 실행하거나 로딩하지 않았다. 울산 80km의 두 배치 지점만 작은 지형 패치로 렌더링해 확인했다. 높이맵 검증용 원본 PNG 읽기에 대한 Godot 내보내기 경고는 검증 보조 코드에서 발생하며 새 런타임 배치 모듈은 이미 준비된 지형 관리자의 표고 API를 사용한다.

- 검증: `results/261004_PedestrianBridgePlacementValidation.json`
- 로그: `results/261004_pedestrian_bridge_placement.log`
- 선바위교 배치 이미지: `results/261004_placed_seonbawi_bridge.png`
- 징검다리 배치 이미지: `results/261004_placed_gulhwa_daun_crossing.png`
