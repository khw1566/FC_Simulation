# 울산공항 건물 모델 구성 보고서

## 반영 결과

- 울산 60km 맵에 여객청사, 관제탑, 북측 부속동, 소방대, 전력시설을 별도 3D 자산으로 추가했습니다.
- 청사의 유리 커튼월, 창틀, 금속 지붕, 출입구 캐노피, 기둥과 공항 표기를 구성했습니다.
- 모델은 2,760개 삼각형, 6개 재질별 배치 메시, 건물·캐노피 충돌체로 구성됩니다. 표지판은 별도 3D 텍스트입니다.
- 모델은 `godot_project/assets/maps/ulsan_metro_60km/airport/ulsan_airport.scn`에 저장됩니다.
- 60km 맵을 선택하면 `BuildingRoadManager`가 배치 설정을 읽어 모델을 생성합니다. 건물 캐시 재병합과 독립적으로 유지됩니다.
- 같은 건물 중심에 일반 건물 데이터가 존재하면 일반 건물 렌더링을 생략합니다. 이 처리는 공항 모델이 정상 로드된 경우에만 적용됩니다.
- 건물 바닥은 지형 표본의 최대 높이에 맞추고 각 건물 아래 기초를 지면까지 연장합니다.

## 조사 자료와 정확도

- [국토교통부 RKPU 공항도, 2026-07-08 발효](https://aim.koca.go.kr/eaipPub/Package/2026-07-08-AIRAC/pdf/AD/RKPU/%282-1%29%20AD%20CHART.pdf): 청사·관제탑·소방대·전력시설의 상대 위치와 방향, 주기장 표고를 참고했습니다. 자료 사본은 `data/raw/ulsan_airport/aerodrome_chart_20260708.pdf`입니다.
- [한국공항공사 울산공항 개요](https://www.airport.co.kr/ulsaneng/cms/frCon/index.do?MENU_ID=210): 공항 식별과 청사 설명을 참고했습니다.
- [울산매일 울산공항 전경](https://www.iusm.co.kr/news/articleView.html?idxno=772218): 유리 외벽, 흰색 프레임과 인접 관제탑 외관을 참고했습니다. 사진을 텍스처로 사용하지 않았습니다.
- 공개 지도 외곽 좌표 조회는 서버 응답 오류로 실패했습니다. 따라서 측량 외곽선을 확보한 것으로 처리하지 않습니다.
- 건물 중심 35.59273°N / 129.35592°E 및 방향 94°는 도면에서 판독한 근사 배치입니다. 위치 오차 수십 미터를 고려해야 하며 설정의 30m는 정확도 인증값이 아닙니다.
- 청사 80×44m, 높이 11.8m, 관제탑 안테나 포함 31m와 부속동 치수는 모델링 추정값입니다. 준공 도면 또는 정밀 스캔 모델이 아닙니다.
- 실내, 지하 공간, 실제 설비 상세는 구현 범위에 포함하지 않았습니다.

## 좌표와 실행

- 울산 60km 맵 배치 중심: X=9,068.634m, Z=-5,352.941m.
- 현재 높이맵에서의 모델 바닥: Y=19.993m. 공식 도면의 주기장 표고 9m와는 다르며, 게임 지형에 접지하기 위해 높이맵 값을 사용합니다.
- 모델 미리보기: `previews/preview_ulsan_airport.bat` 실행. 마우스 드래그로 회전하고 휠로 확대합니다.
- 미리보기 장면: `godot_project/scenes/ulsan_airport_preview.tscn`.
- 형태와 배치 수정: `config/ulsan_airport_model.json` 및 `airport_mesh_builder.gd`.
- 재생성: 프로젝트 루트에서 아래 명령을 실행합니다. 이 과정에서 맵 및 generated 자산 매니페스트의 해시·경계·상대 고도·메시 해상도를 갱신합니다.

```powershell
& '.\tools\godot\Godot_v4.3-stable_win64_console.exe' --rendering-method gl_compatibility --path godot_project --script (Join-Path (Get-Location) 'pipeline/processors/build_ulsan_airport_asset.gd')
```

## 확인 결과

- Godot 4.3 모델 생성 완료, 게임 연결 코드 구문 검사 통과.
- 실제 맵 설정과 높이맵으로 모델 배치·청사 영역 중복 제외·외부 영역 유지·메시 로드·청사 수직 충돌 검사 통과.
- OpenGL 렌더러에서 미리보기 이미지 저장 및 시각 확인 완료.
- 헤드리스 검사 종료 시 엔진의 더미 렌더러 경고가 발생하여 실제 OpenGL 렌더러로 재검사했고 오류 없이 통과했습니다.
- 검사 기록: `results/ulsan_airport_validation.json`, 미리보기: `results/ulsan_airport_preview.png`.
- 전체 60km 맵을 대상으로 한 수동 비행 확인은 수행하지 않았습니다.
- 루트 및 Godot 모듈 인덱스를 갱신했으며 추가 소스는 모두 600줄 미만입니다.

