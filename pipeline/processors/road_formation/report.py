"""도로 노반과 표시 거리 작업의 실제 결과와 미검증 범위를 기록한다."""
import json
from pathlib import Path

from verify import ROOT, digest, save


def report():
    folder = ROOT/"results/road_formation"
    build = json.loads((folder/"build.json").read_text(encoding="utf-8"))
    checked = json.loads((folder/"verification.json").read_text(encoding="utf-8"))
    preview = json.loads((folder/"preview.json").read_text(encoding="utf-8"))
    index = json.loads((ROOT/"godot_project/assets/asset_index.json").read_text(encoding="utf-8"))
    for path,sha in checked["source_sha256"].items():
        assert digest(ROOT/"godot_project"/path)==sha,f"검증 후 코드 변경: {path}"
    summary = {"updated_utc":index["updated_utc"],"files":len(index["files"]),"pending":index["pending"],
               "formation_segments":index["categories"]["maps"]["도로 노반 선분"]}
    save(folder/"asset_index_summary.json",summary)
    earth = checked["earthwork"]
    dense = preview["dense_check"]
    renderer = preview["render"]
    lines = ["# 울산 80km 도로 노반 보정·원거리 최적화", "", "작성일: 2026-10-11", "",
             "## 적용 결과", "",
             "- 도로 셰이더가 좌우 정점을 서로 다른 지형 고도로 옮기던 경로를 보정 도로에서 해제했다. CPU가 만든 수평 횡단면을 유지한다.",
             "- 도로 중심선 고도로 실제 근거리 지형 메시를 절토·성토한다. 도로 폭 안은 수평 단면, 외곽은 4~12m 어깨 구간으로 기존 지형에 연결한다. 진행 방향의 오르내림은 유지한다.",
             "- 원본 DEM과 벡터를 보존하고 별도 노반 선분 타일을 사용한다. 철도 보정은 기존 우선순위를 유지한다.",
             "- 도로를 폭·종류·256m 공간 구역별로 분리한다. 분할 경계에서도 커브의 마이터 정점을 유지하고, 실제 도로 메시 범위로 거리·시야 컬링한다.", "",
             "| 도로 구분 | 기준 | 표시 종료 거리 |", "|---|---|---|",
             "| 소형 | 폭 4m 이하, 또는 폭 6m 이하의 보행로·소로 등 | 최대 1.6km |",
             "| 일반 | 소형·주요 도로 이외 | 최대 3.5km |",
             "| 주요 | 간선도로·연결로 또는 폭 9m 이상 | 기존 도로 시야 거리 + 4.5km |", "",
             "- 소형·일반 기준은 기존 시야 거리보다 길어지지 않으며, 경계에서 반복 표시되는 현상을 줄이는 200m 히스테리시스를 둔다.",
             "- 교량·터널은 지상 도로 거리 분류에서 분리된 기존 구조물을 유지한다.", "",
             "## 전체 범위 자료", "",
             f'- 입력 도로 91,468개 중 지상 도로 {build["counts"]["surface"]:,}개를 처리했다. 교량 5,622개·터널 1,403개·계단 560개는 노반 생성에서 제외했다.',
             f'- 노반 선분 {build["segments"]:,}개, 512m 타일 {build["tile_count"]:,}개, 선분 데이터 {build["bytes"]:,}바이트. 중심선 최대 표본 간격 24m.',
             f'- 수계에 걸친 선분 {build["counts"]["water_segments_skipped"]:,}개를 제외했다. 노반 고도 범위 {build["elevation_min"]:.3f}~{build["elevation_max"]:.3f}m.',
             '- 벡터·DEM·수계 입력 해시, 타일별 해시, bbox·고도 범위·비래스터 resolution=null을 색인과 매니페스트에 기록했다.',
             f'- 리비전: `{build["revision"]}`. 원본 벡터 SHA256: `{build["source_sha256"]}`.', "",
             "## 경량 확인", "",
             f'- 합성 128m 경사면: 도로 좌우 고도차 {earth["cross_height_before_m"]:.1f}m에서 {earth["cross_height_after_m"]:.1f}m. 노반 내부 {earth["interior_probes"]}개 지점과 도로 밖 원지형을 확인했다.',
             f'- 삼각형 투영 면적 {earth["preserved_projected_area_m2"]:,.0f}m² 보존, 곡선 분할 전후 정점 동일, 소형·일반·주요 거리 설정과 UV2 보정 표식 확인.',
             f'- 실제 밀집 구역 128×128m·선분 {dense["segments"]}개: 생성 {dense["build_ms"]}ms, 삼각형 {dense["triangles"]:,}개. 공간 색인 높이 조회 {dense["point_bucket_probes"]}개를 전체 후보 검색과 대조했다.',
             f'- 같은 구역의 캐시 높이 조회 {dense["point_bucket_probes"]}회 {dense["cached_point_queries_ms"]:.3f}ms. 단일 실행의 국소 측정이며 전체 맵 성능 수치가 아니다.',
             f'- Godot 4.3 Forward+ 실제 렌더링: {renderer["device"]}. 원본 프로젝트 대신 독립 복사 프로젝트에서 지형·도로 셰이더를 실행했다.',
             '- 헤드리스 형상 검사는 통과했지만 Godot dummy 렌더러의 종료 과정에서 mesh_get_surface_count의 null 오류가 기록됐다. 실제 GPU 비교 렌더 로그에는 스크립트·셰이더 오류가 없었다.',
             '- 통합 관리자 의존성 확인 중 발견된 태화강 수면의 Godot 4.3 미지원 렌더러 조회 API 한 곳을 기존 광학 효과와 같은 RenderingDevice 검사로 교체했다.', "",
             "## 비용 제한과 확인 범위", "",
             '- 정밀 노반은 근거리 LOD0에만 생성하고 LOD 메시 캐시를 재사용한다. 원거리 LOD1·2는 기존 단순 지형이다.',
             '- 선분이 밀집한 구간은 최대 변 길이 2m 이하의 국소 삼각형으로 근사해 도로 경계 절단 조합의 증가를 제한한다. 밀집 교차부·곡선·노반 전환에는 근사 오차가 있을 수 있다.',
             '- 타일 캐시와 16m 공간 색인으로 정점·건물의 높이 조회 시 전체 512m 타일 선분을 반복 검색하지 않는다.',
             '- 기존 높이맵 충돌 격자에는 보정 고도를 반영하지만, 정밀 노반 삼각형과 동일한 충돌 메시로 교체하지 않았다.',
             '- 전체 80km 맵 로딩·주행·FPS 측정과 새 실행파일 패키징은 수행하지 않았다. 전체 범위 자료 생성과 국소 형상·렌더링 확인을 구분한다.', "",
             "## 색인", "",
             f'- 에셋 색인 수동 갱신: {summary["files"]:,}개 파일, 도로 노반 선분 {summary["formation_segments"]:,}개, 보류 {len(summary["pending"])}개.',
             f'- 색인 시각: {summary["updated_utc"]}. 루트·Godot·도로 노반 도구의 모듈 색인도 갱신했다.', "",
             "## 증거 파일", "",
             f'- [형상·거리·입력 보존 결과]({folder.as_posix()}/verification.json)',
             f'- [밀집 구역·GPU 결과]({folder.as_posix()}/preview.json)',
             f'- [보정 전]({folder.as_posix()}/before.png)',f'- [보정 후]({folder.as_posix()}/after.png)',
             f'- [에셋 색인 요약]({folder.as_posix()}/asset_index_summary.json)', ""]
    if summary["pending"]:
        lines += ["보류 파일:", ""]+["- "+p for p in summary["pending"]]+[""]
    output = ROOT/"results/261011_RoadFormationAndDistanceOptimizationReport.md"
    output.write_text("\n".join(lines),encoding="utf-8")
    print(output)


if __name__=="__main__":
    report()
