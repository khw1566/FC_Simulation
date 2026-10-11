"""광학 렌더링·건물 그림자 확인과 실제 에셋 색인 결과로 한국어 보고서를 작성한다."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def report():
    results = ROOT / "results/optical_effects"
    forward = json.loads((results / "forward_plus.json").read_text(encoding="utf-8"))
    compatibility = json.loads((results / "gl_compatibility.json").read_text(encoding="utf-8"))
    index = json.loads((ROOT / "godot_project/assets/asset_index.json").read_text(encoding="utf-8"))
    pending = index.get("pending", [])
    image = forward["image_metrics"]
    content = f'''# 광학 그래픽 및 소형 밀집 건물 그림자 최적화
작성일: 2026-10-11. 울산 80km를 포함해 기존 메인 월드의 구름 관리자와 건물 메시 생성 경로에 적용했다.

## 구현 결과
- 렌즈 플레어: 태양 주변의 옅은 후광·수평 스트릭·렌즈 고스트. 화면 밖·카메라 뒤·야간에는 차단하고 태양 위치 주변 깊이 5표본과 구름 투과율로 가림을 반영한다.
- 구름 그림자: 불투명 지형·도로·건물의 월드 위치에서 태양 쪽 구름 투과율을 계산해 곱셈 합성한다. 하늘 구름보다 먼저 그리며 안개로 가려진 원경은 약화한다. 기본 최대 강도는 0.32다.
- 구름 틈의 안개 광선: 카메라 광선을 따라 안개의 태양 산란을 누적한다. 화면 깊이와 구름 밑면에서 표본 범위를 제한한다. 기존 구름과 동일한 밀도장·고도·바람을 사용한다. 기본 강도는 0.75다.
- 구름 품질 0/1/2/3에 따라 광선 표본 수를 8/6/4/2로 제한한다. 맑음에는 구름 그림자와 광선 패스를 생략한다. 플레어의 깊이·구름 조회는 실제 후광·고스트가 기여하는 픽셀에서만 수행한다.
- 기존 안개 끄기는 광선을, 그림자 끄기는 구름 지면 그림자를 차단한다. 주야간 전환 시 달을 향한 방향광으로 태양 플레어가 생기지 않는다. 날씨·구름 비활성 설정을 따른다.

## 밀집 건물 최적화
- 높이 12m 이하, 최대 바닥 폭 16m 미만, 바닥 바운딩 면적 140㎡ 이하인 소형 건물이 대상이다.
- 같은 스트리밍 공간 배치에서 반경 35m 안의 다른 소형 건물이 6채 이상 확인되면 그림자 없는 메시 묶음에 배치한다.
- 대형·고층·외딴 건물과 캠퍼스·랜드마크 표식 건물의 기본 그림자는 유지한다. 건물 정점·재질·거리 소거·충돌용 정점은 보존한다. 건물별 노드를 추가하지 않는다.
- 배치 경계를 넘는 미확인 이웃을 추정하지 않는 보수적 정책이다. 경계의 일부 밀집 건물은 기존 그림자를 유지할 수 있다. 전체 지도 건물의 그림자를 일괄 해제하지 않는다.

## 독립 확인 결과
- Godot 4.3, NVIDIA GeForce RTX 4070 SUPER, 960×540 소형 장면에서 Forward+와 Compatibility 실제 GPU 렌더링을 확인했다.
- 밀집 건물 9채 그림자 제외, 외딴·고층·캠퍼스 3채 기본 그림자 유지. 폴리곤·박스와 음수 좌표 격자를 포함했으며, 분리 전후 정점 다중집합과 충돌용 정점 보존을 확인했다.
- Forward+ 광선 켜기/끄기 비교: {image['rays']['changed_pixels']:,}픽셀 변화. 플레어 켜기/끄기 비교: {image['flare']['changed_pixels']:,}픽셀 변화. 태양을 불투명 물체로 가린 뒤 플레어 켜기/끄기의 최대 RGB 차이는 {image['occluded_flare']['max_rgb_difference_255']:.0f}/255다.
- Compatibility에서도 동일한 광선·플레어 기여와 태양 가림 검사를 통과했다. Godot 4.3의 역방향 깊이에서 하늘 값 0을 처리하도록 기존 구름 패스도 맞췄다.
- 두 렌더러에서 안개·그림자 설정과 야간 차단을 확인했다. 최종 렌더링 로그에 엔진·스크립트·셰이더 오류가 없다.
- 전체 80km 지도 실행, 전체 지도 FPS·그림자 패스 절감률, 배포 EXE/PCK 재빌드는 수행하지 않았다. 광선은 제한된 공간 표본으로 계산하는 시각적 근사이며 완전한 다중 산란 대기 해석이 아니다.

## 파일과 재현
- 런타임: `godot_project/scripts/weather/optical_effects_controller.gd`, `procedural_cloud_manager.gd`, `cloud_layer_factory.gd`.
- 건물: `godot_project/scripts/terrain/building_shadow_policy.gd`, `building_mesh_builder.gd`.
- 셰이더: `godot_project/shaders/optics/`의 6파일과 공유 밀도장을 참조하는 `sky_cloud_layer.gdshader`.
- 독립 확인: `.venv_campus/Scripts/python.exe -X utf8 pipeline/processors/optical_effects/verify.py --render --method forward_plus` 또는 `--method gl_compatibility`.
- 원본 Godot 에디터·임포터는 실행하지 않았다. 복사본·로그·캐시는 프리뷰 전용 경로에만 기록했다. 각 확인 JSON에 실제 확인 소스의 SHA256을 기록했다.
- 모듈 색인: 프로젝트 루트와 `godot_project/module_index.json`, 도구 전용 `module_index.json`에 병합했다. 모든 이번 대상 소스는 600줄 미만이다.
- 에셋 색인: `.venv_campus/Scripts/python.exe pipeline/indexer/build_asset_index.py` 실행. {len(index['files']):,}파일, 보류 {len(pending)}개, 갱신 시각 {index.get('updated_utc', '미기록')}. 셰이더 6파일 추가, 하늘 구름 셰이더 수정, 에셋 삭제 없음. 기존 셰이더 분류를 유지하고 지침에 공유 규약을 기록했다.

## 확인 이미지
[효과 적용](optical_effects/forward_plus_optics.png) · [적용 전](optical_effects/forward_plus_baseline.png) · [광선만](optical_effects/forward_plus_rays_only.png) · [맑음 플레어](optical_effects/forward_plus_clear_flare.png) · [태양 가림](optical_effects/forward_plus_occluded.png)

근거: `results/optical_effects/forward_plus.json`, `gl_compatibility.json`, 각 `_image_metrics.json`, `previews/asset_browser/optical_effects_check/` 로그.
'''
    assert forward["settings_and_night"] and compatibility["settings_and_night"]
    target = ROOT / "results/261011_OpticalGraphicsAndBuildingShadowReport.md"
    target.write_text(content, encoding="utf-8")
    print(target)


if __name__ == "__main__":
    report()
