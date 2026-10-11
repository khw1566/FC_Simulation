# 공원·정원 공용 에셋 첫 묶음
범용 절차 모델이며 태화강 국가정원의 실제 종·품종·배치를 재현했다고 주장하지 않는다. 1단위=1m, Y=0 지표 기준이다.

- 16종, 46 LOD 모델. 불투명 정점색, 모델당 표면 1개, 외부 텍스처 없음.
- batch_factory.gd의 add_batches(parent, key, transforms)는 32m 청크 MultiMesh를 생성한다. 개별 LOD 거리와 소거는 catalog.json을 참조한다.
- 풀은 60m 이후 소거한다. 넓은 바닥은 ground_*.tres 5종으로 표현하고 풀 메시로 채우지 않는다.
- 작은 잎의 바람은 surface.gdshader의 wind_strength로 조정한다. 기본값 0이며 조립 예제는 0.04다. 바닥과 조경석은 움직이지 않는다.
- 생울타리 접속점은 catalog.json의 connection_ports에 기록한다. 모서리는 L자, 끝단에는 한 개의 접속점이 있다.
- compositions/의 5개 씬은 독립 배치 예제다. 기존 수목·대나무·벤치·보행로를 읽기 전용으로 참조한다. 실제 좌표는 없다.
- 생성: 명시적 Python으로 pipeline/processors/park_vegetation/generate.py 실행.
- 검증은 previews/asset_browser/park_vegetation_check에서만 수행한다. 게임에 자동 연결하지 않는다.
