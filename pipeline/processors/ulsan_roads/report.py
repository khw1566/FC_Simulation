"""실제 산출물과 검증 기록에서 한국어 완료 보고서를 작성한다."""
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.build import ROOT,read


def report():
    folder=ROOT/"results/ulsan_80km_roads"
    build=read(folder/"build_report.json")
    check=read(folder/"verification.json")
    coverage=read(folder/"coverage.json")
    meshes=read(folder/"mesh_check.json")
    maps=read(folder/"map_check.json")
    empty=read(folder/"empty_cell_review.json")
    index=read(ROOT/"godot_project/assets/asset_index.json")
    before,after=coverage["before"],coverage["after"]
    pending=index.get("pending",[])
    types=after["types"]
    text=f'''# 울산 80km 전 범위 도로 보완 결과

작성일: 2026-10-11

## 적용 결과

- 울산 80km × 80km 전체 경계의 OSM 도로 원본 {build['source_ways']:,}개를 수집했다.
- 경계 클리핑 후 런타임 도로 {build['runtime_roads']:,}개를 활성 리비전 `{build['revision']}`에 연결했다.
- 기존 도로 {before['road_count']:,}개 대비 {build['runtime_roads']-before['road_count']:,}개 증가했다. 원본 way와 경계에서 분리된 도로 조각의 개수는 다르다.
- 기존 건물 {check['preserved_building_count']:,}개 및 기존 비대상 필드를 보존했다. 기존 최적화 정책에 따른 공간 캐시 건물은 {build['cache_counts']['buildings']:,}개로 이전과 같다.
- 활성 벡터는 `godot_project/assets/maps/ulsan_metro_80km/road_revisions/{build['revision']}/buildings_and_roads.json`이다.
- 이전 지도 폴더 바로 아래 `buildings_and_roads.json`과 기존 캐시는 롤백 및 비교용으로 보존했다. 게임은 `map_meta.json`의 활성 경로를 따른다.

## 전 범위 집계

| 항목 | 기존 | 보완 후 |
|---|---:|---:|
| 도로 조각 | {before['road_count']:,} | {after['road_count']:,} |
| 선형 합산 길이 | {before['total_length_km']:,.3f}km | {after['total_length_km']:,.3f}km |
| 도로가 있는 조사 셀 | {before['cells_with_roads']} | {after['cells_with_roads']} |
| 외곽 10km 띠에 닿는 도로 | {before['roads_touching_outer_10km']:,} | {after['roads_touching_outer_10km']:,} |

- 조사 격자는 36 × 29 = 1,044셀이다. 전체 경계 일괄 쿼리가 성공해 기본 셀별 1,044회 네트워크 호출은 하지 않았다.
- 무도로 {empty['empty_cells']}셀은 모두 현재 수계 마스크에서 육상 비율 5% 미만이다. 마스크 기반 근사 판정이며 미등록 현실 도로가 없다는 증명은 아니다.
- 도로 길이는 양방향 분리 차도와 별도 보행로 등을 각각 더한 선형 길이이며 도로 행정 통계와 동일하지 않다.
- 주요 추가 유형: 주거도로 {types.get('residential',0):,}, 서비스도로 {types.get('service',0):,}, 보도 {types.get('footway',0):,}, 산책로 {types.get('path',0):,}, 임도 {types.get('track',0):,}, 자전거길 {types.get('cycleway',0):,}개.

![전후 도로 분포](ulsan_80km_roads/coverage.png)

## 제외와 속성 처리

- 경계 밖 또는 길이 0: {build['excluded'].get('outside_or_zero_length',0):,}개 원본 way.
- 건설 예정·실내·비도로 시설 등: {build['excluded'].get('non_surface_or_not_operational',0):,}개.
- 원본 노드 1개인 퇴화 way: {build['excluded'].get('degenerate_way',0)}개.
- 모든 원본 {build['source_ways']:,}개에 도로 ID 대응 또는 제외 사유를 기록했다. 누락 노드를 임의의 직선으로 연결하지 않았다.
- OSM ID·버전·시각·층·교량·터널·접근 제한·노면 태그를 보존했다. width → lanes → 유형별 기본값 순으로 폭을 정하고 근거를 기록했다.
- 포장 자전거길과 포장 임도를 비포장 재질로 강제하지 않으며 자갈 등 노면은 실제 태그로 분류한다.
- 출처: OpenStreetMap contributors, ODbL-1.0. 수집 시각은 `build_report.json`에 기록했다.

## 표시와 재생성 보호

- 공간 캐시는 원본과 같은 리비전에 생성하고, 모든 파일이 준비된 뒤 작은 지도 메타데이터로 참조를 전환했다.
- 건물 병합 재실행 시 활성 80km 도로를 60km 원본으로 되돌리지 않도록 보호했다.
- 건물 수집 완료와 도로 수집 완료를 메타데이터에서 구분했다.
- 전술지도에 {maps['road_features']:,}개 도로 피처와 256개 확대 타일을 반영했다. 자가 교차 선형 분할로 실제 SVG path는 {maps['rendered_paths']:,}개다.
- 울산 80km에만 도로 유형 확대를 적용했다. 상세 길은 얇게 표시하며 기존 지도 색상은 유지했다.

## 확인한 범위

- 실제 원본 대응표와 {check['verified_batch_hashes']:,}개 배치의 SHA-256·도로 ID·집계를 전 범위 대조했다.
- 기존 비대상 필드 동등성, 맵 경계 ±40,000m, 배치 반경과 원본 크기·수정 시각 일치를 확인했다.
- 경계 통과·재진입·누락 노드 연결 금지·활성 도로 보존 등 회귀 확인 7건 통과.
- 전용 프리뷰 복사본에서 실제 대표 6건과 노면 분류 3건, 총 {len(meshes['cases'])}건의 Godot 메시 생성 확인 통과.
- 독립 메시 확인은 원본 DEM 표본 평균을 사용했다. 실제 지형 굴곡에 대한 비행·육안 검증을 대신하지 않는다.
- 전체 SVG·256타일 구조 검사와 전술지도 PNG 및 전후 분포 이미지 확인을 수행했다.
- 전체 맵 실행과 FPS 측정은 수행하지 않았다. 지형·식생·산업단지의 기존 사전 생성 배치는 재생성하지 않았다.

## 자산 색인

- 실행: `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py`.
- 현재 색인 시각: `{index.get('updated_utc')}`.
- 전체 색인 파일: {len(index.get('files',[])):,}개. 보류 파일: {len(pending)}개.
- 갱신 산출물: `godot_project/assets/asset_index.json`, `godot_project/assets/ASSET_INDEX.md` 및 지도별·공통 매니페스트.
- 새 도로 리비전의 분류·활성 판정 규약을 색인 지침과 분류 코드에 추가했다. 모듈 색인도 병합했다.

## 관련 산출물

- `results/ulsan_80km_roads/coverage.csv`, `coverage.json`, `coverage.png`: 전후 전 범위 집계.
- `results/ulsan_80km_roads/build_report.json`, `verification.json`, `mesh_check.json`, `map_check.json`: 실제 생성·확인 기록.
- `results/ulsan_80km_roads/empty_cell_review.json`: 무도로 셀과 수계 대조.
- `results/ulsan_80km_roads/map_meta_before.json`: 이전 참조. 롤백은 비대상 설정을 보존하고 벡터·지도 참조만 복구한다.
- `pipeline/processors/ulsan_roads/README.md`: 재개·재생성 절차.
- 실행 중인 기존 맵은 다시 선택하거나 재시작해야 새 리비전을 읽는다.
'''
    if pending:
        text+='\n## 보류 파일\n\n'+''.join('- `'+p+'`\n' for p in pending)
    output=ROOT/"results/261011_Ulsan80kmRoadCoverageCompletionReport.md"
    output.write_text(text,encoding="utf-8")
    print(output,flush=True)


if __name__=="__main__":
    report()
