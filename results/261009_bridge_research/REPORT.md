# 태화강 교량 조사 기반 에셋 1차 작업

## 후속 작업 현재 상태

2026-10-09 후속 작업으로 초안은 총 9종이다. 아래 최초 작업 기록의 6종에 망성교·구영교·선바위교 도로교 수정 초안을 더했다. 현재 `generation.json` 및 `godot_glb_check.log`는 9종 기준이다. 전체 맵 적용과 실제 사진·표고 대조는 여전히 남아 있다.

| 추가 모델 | 제원 | 구조 반영 | 삼각형 수 |
|---|---|---|---:|
| 망성교 | 126 × 8.5m | 7경간·RC 슬래브·T형 교각 | 204 |
| 선바위교 도로교 수정 초안 | 160 × 24.9m | 3경간·강상자형·라멘식 교각 | 156 |
| 구영교 | 150 × 25m | 6경간·PSC I형·라멘식 교각 | 420 |

사용자 PDF의 링크인 [망성교](https://krbridge.com/망성교-울산광역시-울주군/), [선바위교](https://krbridge.com/선바위교-울산광역시-울주군/), [구영교](https://krbridge.com/구영교-울산광역시-울주군/) 페이지를 직접 열어 대조했다. 민간 교량 DB이므로 공식 준공도면 검증과 구분한다. 망성교의 7 × 18m 및 구영교의 6 × 25m는 총연장과 최대경간에 맞췄고, 선바위교의 50+60+50m는 대칭 근사로 명시했다. 세 모델 모두 실제 교각 단면·기초 깊이·표고는 미확인이다. 기존 선바위 보행교는 보존했으며 도로교와 혼용하지 않는다.

Godot 4.3의 격리 GLB 읽기 확인은 `GLB READ OK: 9`로 통과했다. 기존 교량 씬 8개 해시도 보존했다. 현재 에셋 색인은 공단 원경 작업과 함께 갱신했으며 쓰기 중 보류는 0개다.

## 최초 6종 작업 기록

2026-10-09. 사용자 제공 `C:/Users/work/Downloads/태화강 교량 목록.pdf` 4쪽을 읽고 1쪽 렌더를 확인했다. Claude 링크는 로그인 화면으로 열려 본문을 읽지 못했으며 PDF로 조사 기준을 대체했다.

## 산출물

- `godot_project/assets/generated/bridges/research_20261009/`에 GLB 6개와 대응 `.tscn` 6개를 생성했다. 모델 종류는 6개다.
- `pipeline/processors/bridge_research/`에 제원, 기하, 생성, 프리뷰, 경량 확인 모듈을 나누고 `__init__.py`와 `module_index.json`에 노출했다.
- 기존 교량 씬 8개를 덮어쓰지 않았다. 생성 전후 SHA256 일치는 `generation.json`에 기록했다.
- 전용 manifest/catalog, 공통 generated/manifest와 중앙 에셋 색인을 갱신했다. 중앙 색인의 파일 쓰기 보류는 0개다. 에셋 삭제 없음.
- 원본 프로젝트 임포터·에디터·게임·전체 맵 실행과 프리뷰 실행파일 재빌드는 수행하지 않았다.

| 모델 | 삼각형 수 | 반영 사항 | 남은 확인 |
|---|---:|---|---|
| 울산대교 수정 초안 | 6,716 | PDF 1,800m 구간, 주경간 1,150m, 주탑 상단 203m, 중앙 경간 수직 행어, U형 상부 개구, 독립 정착부 | 실제 주탑 좌표, 케이블 처짐, 주탑 단면, 접속부 종단 및 상세 사진 |
| 태화교 초안 | 1,200 | 440m, 두 동 분리, 합계 폭 35m | 17.5m씩 폭 균등 배분은 임시. 구교·신교 상부 단면 세부 구분 |
| 울산교 보행교 초안 | 348 | 356m, 목재 데크 표현 | 폭 5m는 자료값이 아닌 임시값. 교각·난간 세부 |
| 번영교 초안 | 672 | 333m, 두 동 및 상자형 거더 | PDF의 25m(2동)를 각 동 25m로 해석. 합계 폭 여부 확인 필요 |
| 학성교 초안 | 840 | 458m, 합계 폭 30m, 슬래브 표현 | 15m씩 폭 균등 배분은 임시. 실제 중공 단면 및 교각 위치 |
| 명촌교 초안 | 1,260 | 550m, 폭 19.8/20m, I형·상자형 구분 | 두 동 간격·실제 단면·교각 위치 |

이 모델들은 `status=research_draft`인 직선 로컬 형상이다. 참고 중심좌표와 실제 배치를 분리했고 bbox와 resolution은 null로 기록했다. 교각 간격·깊이·두 동 간격 0.8m·상세 단면은 근사다. 충돌, 차선 표시, 야간 조명, 실제 선형과 DEM 적용은 아직 없다. 게임용 확정 에셋이나 실측 복원으로 보지 않는다.

## 울산대교 기존 구현과 수정 방향

기존 `taehwa_bridges.json`의 지도 경로는 생성기의 미터 환산법으로 약 2,995.9m다. 기존 빌더는 전체 경로 중앙에 주경간을 놓고, 지형 없는 독립 출력에서 상판 양 끝을 1m로 내린다. 원래 데이터와 실행 빌더는 그대로 보존했다.

수정 초안은 PDF에 적힌 1,800m 교량 구간을 별도 모델로 만들고 상판을 65m로 유지했다. 65m는 PDF에 명시된 추정값이며 확정 표고가 아니다. 203m 역시 로컬 원점 기준 상단 Y값이며 실제 기초 높이를 복원한 값이 아니다. 주탑 위치를 양끝에서 각각 325m로 둔 것도 독립 모델의 대칭 근사다.

주경간·주탑 수치에는 [현대건설 사보 2016-01-27](https://www.hdec.kr/FileContents/OldFiles/HDEC_NEWSPAPER/005925539.pdf), 중앙 행어와 U형 주탑 해석에는 [UNIST Magazine 26호](https://webzine.unist.ac.kr/pdf/unist_No.26.pdf)의 공개 설명을 참고했다. 상세 도면·사진 대조는 남아 있다. 단순히 기존 모델을 완성도 높은 실물 모델로 교체했다고 주장하지 않는다.

## 다음 제작 대상과 조사 보류

- 국가정원교·은하수다리: 상하부 관계는 확인. 실제 폭·보행교 연결·표고·사진을 확인한 뒤 제작한다.
- 울산고가: OSM 725m 구간의 접속부 포함 여부, 복선 간격과 교각 제원을 확인한다.
- 나머지 도심 및 상류 교량: 좌표·명칭·기존 모델 여부를 순차 대조한다. 상류 목록은 PDF에서 개별 좌표가 확인되지 않았다.
- 제2명촌교 및 도시철도 예정 교량: 공사·계획 상태와 준공된 시설을 분리한다.
- 기존 선바위교 및 십리대밭교 등: 이번에는 수정하지 않았다. 사진·제원 대조 후 별도 리비전으로 처리한다.

위 항목은 조사·제작 보류 4개 그룹이며 중앙 색인 파일 보류 0개와 다른 의미다.

## 확인 결과와 재실행

- 실제 GLB 헤더·파일 길이·인덱스 삼각형 수·유한 정점 검사를 통과했다.
- 실제 생성 메시의 측면·사시 PNG를 열어 확인했다. `research_preview.png`는 메시 투영 이미지이며 Godot 렌더 캡처가 아니다.
- `previews/asset_browser/bridge_research_check`만 사용하는 Godot 4.3 GLTFDocument 읽기에서 `GLB READ OK: 6`을 확인했다. 로그: `godot_glb_check.log`.
- 대응 `.tscn`의 Godot 임포트 및 실제 지도 배치는 확인하지 않았다.

```powershell
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/processors/bridge_research/generate.py
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/processors/bridge_research/check.py
```

필수 색인 명령 `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py`는 실행했으나 가상환경이 `C:/Users/khw/.cache/.../python.exe`를 참조해 실패했다. 공유 가상환경을 변경하지 않고 다음 명시적 설치 경로로 같은 색인 스크립트를 실행했다.

```powershell
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/indexer/build_asset_index.py
```

결과는 전체 40,034개 파일, 쓰기 중 보류 0개. `asset_index.json`과 `ASSET_INDEX.md`가 갱신됐으며 새 파일은 기존 `bridges` 분류에 포함됐다.
