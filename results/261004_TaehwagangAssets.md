# 태화강역 및 주변 구역 에셋 제작
태화강역의 2021년 신축 역사 외관과 공개 환승시설 설명을 참고하여 역사·역전 구역의 독립 정적 에셋을 제작했다. 실측 자료가 없으므로 치수와 배치는 제작용 근사이며, 주변 건물은 특정 실재 건물의 정밀 복제물이 아니다.

## 제작 결과
- 전체 구역은 약 480×580m의 제작용 로컬 범위다.
- 역사: 파형 지붕, 사선 리브, 유리 입면, 정면 출입부, 캐노피, 계단·경사로 및 후면 통로.
- 승강장·선로: 제작용 선로 4개와 승강장 2개, 캐노피, 레일, 침목, 전차선과 울타리.
- 광장: 보행 포장, 식재, 벤치, 가로등, 버스·택시 승하차 구역, 쉼터, 제작용 54면 주차장과 자전거 거치 시설.
- 주변 구역: 도로·보도, 상업·주거 및 보조 건물 14동과 완충 식재.
- 통합 모델 1종과 개별 구성 4종을 각각 GLB·PackedScene으로 제공했다. 통합 모델은 22,536개 삼각형이다.
- 역사와 통합 씬에는 태화강역 역명 표기를 포함한다. 개별 모델은 동일한 좌표계에서 조합할 수 있다.
- 출력 경로는 `godot_project/assets/generated/taehwagang/`이다. 생성·검증 코드는 `pipeline/processors/taehwagang/`, 설정은 `config/taehwagang_asset.json`에 분리했다.
- 전용 매니페스트 및 공용 자산 매니페스트에 해시·크기·경계·고도·해상도를 기록하고 두 모듈 인덱스에 등록했다. 공용 JSON은 최신 내용을 읽어 해당 항목만 병합하고 쓰기 직전 변경을 확인한다.
- 기존 지도, 선박, 철도 운행 및 다른 에셋 생성 코드는 수정하지 않았다.

## 검증
- 5종 GLB의 컨테이너 길이, 버퍼 범위, 삼각형 수, 유한 좌표와 단위 법선을 검사했다.
- 별도 임시 Godot 4.3 프로젝트에서 5종 PackedScene의 로딩·인스턴스 생성 및 `Visual`, `GroundOrigin` 노드와 역명 노드를 확인했다.
- 실제 OpenGL Compatibility 렌더러에서 독립 프리뷰의 5개 선택 전환이 통과했고 런타임 오류 없이 종료했다.
- 실제 렌더 캡처는 `261004_TaehwagangRender.png`, 수치 결과는 `261004_TaehwagangValidation.json`, 로그는 `261004_TaehwagangGodot.log`다.
- Windows 편집기 설정 저장 오류와 자동 LOD 생성의 비유한 법선 경고가 가져오기 단계에서 출력됐다. 원본 메시의 좌표·법선 검사는 통과했으며 실제 렌더러의 씬 로딩과 프리뷰 실행도 통과했다. 자동 LOD 품질은 검증하지 않았다.
- 기존 맵 로딩은 수행하지 않았다. 실제 지도 좌표·방향·표고 및 OSM 철도와의 정합, 기존 건물 중복 제거는 별도 배치 작업이 필요하다.

## 사용
`previews/preview_taehwagang.bat`를 실행하면 전체 지도 없이 프리뷰를 볼 수 있다. 제작용 에셋의 세부 범위, 재생성 명령과 참고 자료는 전용 에셋 폴더의 README.md에 기록했다.

## 참고 자료
- [신축 역사 및 고래 형상](https://www.yna.co.kr/view/AKR20210312072500063)
- [국가철도공단 태화강역 현장 자료](https://www.kr.or.kr/boardCnts/view.do?boardID=52&boardSeq=1117824&page=275&prntBoardID=0&prntBoardSeq=0&prntLev=0)
- [울산시 광장·주차장 조성](https://ulsan.go.kr/u/metro/transfer/alimi/complete/view.ulsan?mId=001008008002002000&nttNo=102)
- [울산시의회 환승 동선 및 쉼터 설명](https://www.council.ulsan.kr/minutes/assembly/bbs2/writtenQnaandview.do?NTT_ID=F90217C791A68804E06595EADCB6391C&flag=all&keyword=&listCnt=10&list_style=&page=10&schwrd=)
