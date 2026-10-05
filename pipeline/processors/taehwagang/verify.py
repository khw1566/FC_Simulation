"""기존 맵과 분리된 임시 Godot 프로젝트에서 에셋을 검증한다."""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT/'godot_project/assets/generated/taehwagang'
ENGINE = ROOT/'tools/godot/Godot_v4.3-stable_win64.exe'


def main():
    with tempfile.TemporaryDirectory(prefix='taehwagang_check_',dir=ROOT/'results') as directory:
        project = Path(directory)
        shutil.copytree(ASSETS,project/'assets/generated/taehwagang')
        for path in ('scripts/core/taehwagang_asset_preview.gd',
                     'scripts/player/vessel_preview_camera.gd',
                     'scenes/taehwagang_asset_preview.tscn'):
            target = project/path
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/'godot_project'/path,target)
        (project/'project.godot').write_text('''config_version=5
[application]
config/name="태화강역 경량 검증"
[rendering]
renderer/rendering_method="gl_compatibility"
''',encoding='utf-8')
        (project/'check.gd').write_text('''extends SceneTree

func _initialize() -> void:
    call_deferred("check")

func check() -> void:
    var names := ["station", "rail_yard", "forecourt", "district", "taehwagang_complete"]
    var instances := 0
    for key in names:
        var scene := load("res://assets/generated/taehwagang/%s.tscn" % key) as PackedScene
        if scene == null:
            push_error("씬 로딩 실패: " + key)
            quit(1)
            return
        var model := scene.instantiate()
        if model.get_node_or_null("Visual") == null or model.get_node_or_null("GroundOrigin") == null:
            push_error("에셋 기준 노드 누락: " + key)
            quit(1)
            return
        if key in ["station", "taehwagang_complete"] and model.get_node_or_null("StationName") == null:
            push_error("역명 표기 누락")
            quit(1)
            return
        model.free()
        instances += 1
    var preview := load("res://scenes/taehwagang_asset_preview.tscn") as PackedScene
    if preview == null:
        quit(1)
        return
    var view := preview.instantiate()
    root.add_child(view)
    for frame in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://render_preview.png")
    for key in names:
        view._select(key)
        await process_frame
        if not is_instance_valid(view.model) or view.model.get_child_count() == 0:
            push_error("프리뷰 선택 실패: " + key)
            quit(1)
            return
    view.free()
    print("TAEHWAGANG_PASS scenes=", instances, " preview_selections=5")
    quit(0)
''',encoding='utf-8')
        environment = os.environ.copy()
        environment['APPDATA'] = str(project/'appdata')
        (project/'appdata/Godot').mkdir(parents=True,exist_ok=True)
        logs = []
        for arguments in (['--editor','--quit'],['--script','res://check.gd']):
            display = ['--headless'] if arguments[0] == '--editor' else [
                '--rendering-method','gl_compatibility','--position','-32000,-32000',
                '--resolution','1280x720']
            result = subprocess.run([str(ENGINE),*display,'--path',str(project),*arguments],
                                    capture_output=True,text=True,encoding='utf-8',errors='replace',
                                    env=environment,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
            logs.append(result.stdout+result.stderr)
            errors = [line for line in logs[-1].splitlines() if 'ERROR:' in line]
            # 일부 Windows 환경의 편집기 설정 저장 오류는 에셋 로딩 검사와 구분한다.
            if arguments[0] == '--editor':
                errors = [line for line in errors if not line.startswith('ERROR: Safe save failed.')]
            if result.returncode or errors:
                (ROOT/'results/261004_TaehwagangGodot.log').write_text('\n'.join(logs),encoding='utf-8')
                raise RuntimeError(logs[-1])
        assert 'TAEHWAGANG_PASS' in logs[-1]
        shutil.copyfile(project/'render_preview.png',ROOT/'results/261004_TaehwagangRender.png')
        (ROOT/'results/261004_TaehwagangGodot.log').write_text('\n'.join(logs),encoding='utf-8')
        report_path = ROOT/'results/261004_TaehwagangValidation.json'
        report = json.loads(report_path.read_text(encoding='utf-8'))
        report.update(godot_scenes=5,preview_selections=5,isolated_project=True,
                      rendered=True,runtime_errors=False,
                      editor_settings_save_warning='Safe save failed.' in logs[0],
                      auto_lod_warning='non-finite normal in LOD generation' in logs[0])
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print('TAEHWAGANG_PASS scenes=5 preview_selections=5')


if __name__ == '__main__':
    main()
