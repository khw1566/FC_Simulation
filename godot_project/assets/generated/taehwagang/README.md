# 태화강역 및 역전 구역 에셋
2021년 신축 역사의 고래 형상과 공개 환승시설 자료를 참고한 게임용 정적 외관 모델이다. 실측 치수·실제 선로 수·최신 현장 배치를 재현한 측량 모델은 아니다. 주변 상업·주거 건물은 실제 특정 건물을 복제하지 않은 제작용 블록이다.

| 파일명 | 내용 | 삼각형 수 |
|---|---|---|
| station | 역사 외관, 유리 입면, 파형 지붕, 사선 리브, 출입 캐노피, 계단·경사로, 후면 통로 | 1,836 |
| rail_yard | 제작용 선로 4개와 섬식 승강장 2개, 캐노피, 침목, 레일, 전차선, 계단, 울타리 | 9,396 |
| forecourt | 포장 광장, 식재, 벤치, 가로등, 승하차 구역, 대기쉼터, 주차장, 자전거 거치 공간 | 3,656 |
| district | 480×580m 바닥, 주변 도로·보도, 주변 건물 14동, 완충 식재 | 7,648 |
| taehwagang_complete | 위 4개 구성의 통합 모델 | 22,536 |

- 각 모델은 GLB와 Godot PackedScene으로 제공한다. 외부 텍스처가 필요 없다.
- 모든 개별 에셋은 같은 로컬 좌표를 사용한다. 원점은 역사 중앙의 바닥 Y=0이며, 역사 정면은 +Z다. 1단위는 1m다.
- 통합 모델을 사용하거나 4개 구성 씬을 동일한 원점에서 조합한다. 통합 모델과 개별 모델을 동시에 배치하면 중복된다.
- 역사 및 통합 PackedScene에는 `StationName` Label3D로 역명을 표시한다. GLB 자체에는 문자 텍스처가 없다.
- `GroundOrigin` Marker3D를 바닥 배치 기준으로 사용한다.
- `manifest.json`은 해시, 크기, 고도 범위, 로컬 AABB와 메시 해상도를 기록한다. 비지리 에셋이므로 위경도 bbox는 null이다.
- 기존 OSM 철도 선형과 정합하지 않았다. 실제 맵 배치 전 회전·좌표·지형 고도 및 기존 건물과의 겹침을 별도로 맞춰야 한다.
- 충돌, 내부 공간, 승객, 차량 운행과 신호 제어는 포함하지 않는다.

## 미리보기
프로젝트 루트의 `previews/preview_taehwagang.bat`를 실행하면 기존 맵 없이 에셋 프리뷰가 열린다. 전체 구역·역사·승강장·광장·주변 구역을 선택할 수 있다. 마우스 드래그로 회전하고 휠로 확대한다. R은 시점 초기화, Esc는 종료다.

`station_preview.png`와 `district_preview.png`는 실제 GLB 생성 메시를 소프트웨어로 투영한 이미지다. Godot 렌더 캡처는 `results/261004_TaehwagangRender.png`에 별도로 저장한다.

## 재생성 및 검증
프로젝트 루트에서 프로젝트 가상환경을 사용한다.

```powershell
& .venv_campus/Scripts/python.exe pipeline/processors/taehwagang/generate.py
& .venv_campus/Scripts/python.exe pipeline/processors/taehwagang/verify.py
```

`config/taehwagang_asset.json`에서 제작용 치수를 조절한다. 생성기는 전용 출력 경로와 공용 인덱스의 `taehwagang` 항목을 갱신한다. 공용 JSON은 마지막에 다시 읽어 병합하며 변경을 감지하면 중단한다. 검증기는 임시 경량 Godot 프로젝트에서 가져오기·씬 로딩·프리뷰 선택을 검사하고 검증 폴더를 자동 정리한다.

## 참고 자료
- [신축 역사 개통 및 고래 형상](https://www.yna.co.kr/view/AKR20210312072500063)
- [국가철도공단의 태화강역 지반 보강 현장 설명](https://www.kr.or.kr/boardCnts/view.do?boardID=52&boardSeq=1117824&page=275&prntBoardID=0&prntBoardSeq=0&prntLev=0)
- [울산시 광장·주차장 조성 사업](https://ulsan.go.kr/u/metro/transfer/alimi/complete/view.ulsan?mId=001008008002002000&nttNo=102)
- [울산시의회 환승 동선 및 쉼터 설명](https://www.council.ulsan.kr/minutes/assembly/bbs2/writtenQnaandview.do?NTT_ID=F90217C791A68804E06595EADCB6391C&flag=all&keyword=&listCnt=10&list_style=&page=10&schwrd=)

## 커스텀 에셋 경량 표현

외형과 조립 규격을 유지하며 곡면과 반복 장식을 단순화합니다. GLB는 중복 정점을 공유하고 무광 단색 재질을 사용합니다. 기존 조립 씬·연결점·조명·연기 설정과 충돌 형상은 보존합니다.

- 규약: `custom_low_poly_flat_v1`
- 재생성: `.venv_campus/Scripts/python.exe pipeline/processors/custom_lowpoly/build.py`
- 게임·지도·실행 생성기 변경 없음. 원본 프로젝트에서 임포터를 실행하지 않습니다.
- 이전 PNG는 과거 표현일 수 있습니다. 최신 모델은 독립 에셋 프리뷰에서 확인하세요.
