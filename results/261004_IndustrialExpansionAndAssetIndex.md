# 산업 시설 확장 및 에셋 인덱스
송전탑, 냉각탑, 냉각 팬 설비, 조선용 대형 격납고, 타워 크레인, 갠트리 크레인 6종을 추가했다. 기존 10종과 합쳐 공단 에셋은 16종이다. 실제 비공개 공단 배치를 재현하지 않는 범용 외관이다.

- 출력: `godot_project/assets/generated/industrial/`의 GLB·Godot 씬·catalog·manifest·preview.
- 전체 조사 범위: `godot_project/assets`, `godot_project/shaders`. 모델 외에 지도 리비전, 벡터 타일, 메타데이터도 역할별로 색인한다.
- 전체 조사 결과: `godot_project/assets/ASSET_INDEX.md` 및 `asset_index.json`.
- 수동 색인 실행 결과: 23,133개 파일, 19개 계열, 보류 0개. 이는 파일 수이며 모델 종류 수가 아니다.
- 지침: `pipeline/indexer/ASSET_INDEX_GUIDE.md`. AGENTS.md 3항에 매 작업마다 수동 갱신할 의무를 추가했다.
- 생성 GLB 컨테이너와 메시 AABB를 확인하고 독립 소프트웨어 투영 이미지를 확인했다. 전체 지도와 Godot 원본 임포터는 실행하지 않았다.
- 설비 동작·충돌·내부 공간·전선망은 구현하지 않았다. 원본 게임 씬과 프리뷰 실행파일을 변경하지 않았다.
