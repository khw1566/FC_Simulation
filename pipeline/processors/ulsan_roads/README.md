# 울산 80km 전 범위 도로 갱신

80km 경계 전체의 OSM highway 원본을 수집하고 맵 경계로 자른다. 원본 way ID·층·교량·터널·노면 속성과 폭의 추정 근거를 보존한다. 현재 건물·터널 목록 등 비대상 필드는 그대로 유지한다.

## 실행 순서

프로젝트 루트에서 지정 가상환경으로 실행한다. 네트워크 수집 단계에는 외부 HTTPS 접근이 필요하다.

```powershell
.venv_campus/Scripts/python.exe -X utf8 pipeline/collectors/ulsan_roads/collect.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/build.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/verify.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/preview.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/audit.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/publish.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/simple_maps/generate.py --maps ulsan_metro_80km
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/publish.py --finalize
.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/ulsan_roads/register.py
.venv_campus/Scripts/python.exe -X utf8 pipeline/indexer/build_asset_index.py
```

- 수집기는 검증된 기존 응답을 재사용한다. 같은 원본으로 중단 작업을 재개하는 명령이며 매번 최신 OSM을 재취득하지 않는다.
- 전체 경계 쿼리 성공 시 한 응답으로 전 범위를 처리한다. 실패하면 1,044개 기본 셀을 분할 수집하며 `--cells-only --limit 120`으로 제한할 수 있다.
- 원본 쿼리는 경계에 0.01도 여유를 둔다. 모든 highway를 확보하고 건설 예정·실내·비도로 플랫폼 등을 사유와 함께 제외한다.
- `results/ulsan_80km_roads/coverage.csv`의 1,044셀은 길이 분포 조사 격자다. 일괄 수집 모드에서는 1,044번 API를 호출했다는 뜻이 아니다.
- 원본 경계를 가로지르지만 여유 경계 내부에 노드가 전혀 없는 극단적으로 긴 원본 선분은 Overpass bbox 선택의 한계가 있을 수 있다.
- 완성 리비전은 `maps/ulsan_metro_80km/road_revisions/<revision>/`에 배치한다. 원본 전체 JSON과 모든 캐시 배치가 준비된 뒤 `map_meta.json`의 벡터 참조를 전환한다.
- 기존 지도 폴더 바로 아래의 `buildings_and_roads.json`은 이전 자료로 보존된다. 후속 도구는 `map_meta.json`의 활성 경로를 따라야 한다.
- 지형·철도·식생 등 기존 사전 생성 자산을 도로 변경에 맞춰 재생성하는 작업은 이 도구에 포함하지 않는다. 실행 중인 기존 맵 세션은 다시 선택하거나 재시작해야 새 리비전을 읽는다.
- 수집한 경계·유형에 대한 완료이며, OSM에 등록되지 않은 현실의 도로를 임의 복원하지 않는다.

## 경량 확인

`test_geometry.py`는 경계 재진입·누락 노드 연결 금지·활성 도로 보존을 확인한다. `verify.py`는 실제 원본 대응표·비대상 데이터·배치 해시·도로 ID를 전 범위 대조한다. `preview.py`는 전용 복사본에서 실제 도로 대표 6건의 메시만 만든다. 지형 표본 평균을 사용하므로 지형 굴곡에 대한 시각 검증이나 전체 맵 FPS 검증은 아니다.

## 롤백

`results/ulsan_80km_roads/map_meta_before.json`에 이전 지도 참조가 보존된다. 활성 벡터·지도 이미지 참조만 이전 값으로 되돌리고 공유 매니페스트와 자산 색인을 갱신한다. 다른 작업이 추가한 지도 설정을 덮어쓰지 않는다.
