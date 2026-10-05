"""기존 프리뷰 캐시에 네이티브 최신화 실행파일을 빌드한다."""

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'previews/asset_browser'
COMPILER = Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')


def main():
    runtime = OUT / 'runtime'
    runtime.mkdir(parents=True,exist_ok=True)
    engine = runtime / 'PreviewEngine.exe'
    if not engine.exists():
        shutil.copyfile(ROOT / 'tools/godot/Godot_v4.3-stable_win64.exe',engine)
    native = Path(__file__).parent / 'native'
    target = OUT / 'AssetPreview.next.exe'
    command = [str(COMPILER),'/nologo','/target:winexe','/optimize+',
               '/reference:System.Web.Extensions.dll','/reference:System.Windows.Forms.dll',
               '/out:'+str(target),*[str(file) for file in sorted(native.glob('*.cs'))]]
    subprocess.run(command,check=True)
    target.replace(OUT / 'AssetPreview.exe')
    settings_path = OUT / 'live_settings.json'
    if not settings_path.exists():
        settings_path.write_text(json.dumps({'source_project':'../../godot_project','cache_project':'project'},ensure_ascii=False,indent=2),encoding='utf-8')
    manifest_path = OUT / 'build_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest.update(live_refresh=True,source_access='read_only',refresh_seconds=3,
                    runtime='runtime/PreviewEngine.exe',cache='project',single_writer=True)
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('자동 최신화 실행파일 빌드 완료')


if __name__ == '__main__':
    main()
