# 공단 원경·초원경 에셋

2026-10-09. 기존 공단 16종과 플랜트 12종, 합계 28종에 원경 LOD1·초원경 LOD2를 생성했다. 경로는 `godot_project/assets/generated/industrial_lod/`다. 원본 모델·씬·조명·카탈로그 등 99개 파일의 SHA256을 생성 전후 및 확인 후 대조했고 모두 일치했다.

## 산출물과 감소량

- GLB 56개와 대응 원경 씬 56개. GLB와 대응 씬은 동일 모델의 표현이다.
- 원본 근경과 두 원경 단계를 전환하는 선택형 자동 LOD 씬 28개.
- 전용 catalog/manifest, 공통 generated manifest, README와 단계별 실제 메시 투영 PNG 2개.
- 생성기 모듈은 `pipeline/processors/industrial_lod/module_index.json`과 `__init__.py`로 노출했다.
- 새 분류 `industrial_lod`와 분류 지침을 함께 등록했다. 에셋 삭제 없음.

| 합계 기준 | 원본 28종 | 원경 LOD1 28종 | 초원경 LOD2 28종 |
|---|---:|---:|---:|
| 삼각형 수 | 29,168 | 4,076 | 1,664 |
| 원본 대비 감소 | - | 86.03% | 94.30% |
| GLB 파일 크기 합계 | 1,606,960B | 248,572B | 122,436B |

각 종류를 한 번씩 합산한 값이다. 실제 배치 수에 따른 가중치나 전체 맵 FPS를 의미하지 않는다. 종류별 비교값과 원본 해시는 `generation.json`에 있다.

## 표현과 사용

사다리·난간·반복 트러스·작은 설비를 줄이고 공장 지붕, 탱크, 연통, 크레인과 송전탑의 주요 실루엣을 남겼다. 원경 GLB는 단일 표면·무광 단색이며 외부 텍스처가 없다. 초원경 배관은 3열을 묶은 각형 부재로 표현한다. 기하 원점은 보존했지만 생략·근사에 따라 실제 로컬 AABB는 원본과 다를 수 있다. 원본과 파생본의 AABB를 모두 기록했다.

원경 씬에는 충돌·실제 광원·연기 파티클이 없다. 원경 전용 스크립트가 그림자 투사를 끈다. 배관 포트 좌표·방향·프로파일 및 연기 배출구 Marker3D는 남겼다. GLB만 MultiMesh로 사용할 경우 그림자 설정은 배치 측에서 꺼야 한다.

선택형 `*_auto_lod.tscn`은 근경 원본을 포함한다. 0.25초 간격으로 카메라 거리를 확인하고 기본 350/1200/10000m 이상에서 단계 전환·소거한다. 모델 크기에 따라 거리를 확대하며 5% 히스테리시스를 사용한다. 값은 씬 export 속성에서 변경할 수 있다. 원경으로 전환하면 숨긴 근경의 처리와 파티클 방출도 중지한다. 모델 로컬 원점 기준 거리이며 실제 배치 후 화각·스케일에 따른 조정이 필요하다.

자동 씬은 개별 확인과 소규모 배치용이며 세 단계 리소스를 함께 로드한다. 대량 반복 사용에는 카탈로그의 단일 표면 GLB를 사용하는 MultiMesh 배치를 권장한다. 게임·공단 배치·공유 월드에는 연결하지 않았다.

## 확인 결과

원본 프로젝트를 실행하지 않고 `previews/asset_browser/industrial_lod_check`에 안정된 의존성만 복사해 Godot 4.3에서 임포트·확인했다.

- 원경 씬 56개 인스턴스 생성과 실제 메시 삼각형 수 대조 통과.
- 원경 메시 단일 표면·그림자 끄기, 충돌·광원·파티클 부재 확인 통과.
- 연결 마커 좌표 대조 통과.
- 자동 선택기 28개 근경→원경→초원경→소거→근경 복귀 확인 통과.
- 경계 히스테리시스 및 숨긴 근경의 처리·파티클 중지 확인 통과.
- 실제 생성 메시의 원경·초원경 PNG를 열어 확인했다. Godot 화면 캡처는 아닌 소프트웨어 투영이다.

`check.log`: `INDUSTRIAL LOD OK: 56 models, 28 selectors`.

초기 격리 임포트에서 Godot 자체 LOD 생성 중 `Ignoring face with non-finite normal in LOD generation` 경고가 1회 있었다. 원본과 파생 모델을 함께 임포트해 발생 대상을 특정하지 않았다. 원경 56종의 본 메시 읽기·표면·삼각형 수 대조에는 실패가 없었다. 이 경고를 원본 문제라고 단정하지 않으며, 전체 맵 성능·장시간 렌더는 확인하지 않았다.

## 재생성과 색인

```powershell
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/processors/industrial_lod/generate.py
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/processors/industrial_lod/check.py
```

지정 명령 `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py`는 실행했으나 가상환경의 이전 사용자 Python 경로 참조로 실패했다. 환경을 변경하지 않고 아래 명시적 설치 경로로 같은 색인 스크립트를 실행했다.

```powershell
& 'C:/Users/work/AppData/Local/Programs/Python/Python312/python.exe' pipeline/indexer/build_asset_index.py
```

최종 색인 결과는 교량 후속 작업과 동시 변경을 포함해 전체 40,200개 파일, 파일 쓰기 보류 0개다. 공단 원경 자산은 모두 생성했으며 보류 파일이 없다. 교량의 실제 치수·사진·지도 배치 조사 보류는 별도 교량 보고서에 기록했다.
