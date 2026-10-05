"""독립 프리뷰만 짧게 실행하여 패키지 열람과 렌더를 검증한다."""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'previews/asset_browser'


def main():
    environment = dict(os.environ)
    environment['APPDATA'] = str(OUT / 'build_environment/roaming')
    environment['LOCALAPPDATA'] = str(OUT / 'build_environment/local')
    environment['ASSET_PREVIEW_ROOT'] = str(OUT)
    capture = '--capture' in sys.argv
    source = '--source' in sys.argv
    engine = ROOT / 'tools/godot/Godot_v4.3-stable_win64.exe' if source else OUT / 'AssetPreview.exe'
    args = [str(engine),'--position','-2000,-2000','--resolution','1440x900','--quit-after','1200']
    if source:
        args += ['--path',str(OUT / 'project')]
    args += ['--','--capture' if capture else '--smoke']
    live = not source and json.loads((OUT / 'build_manifest.json').read_text(encoding='utf-8')).get('live_refresh',False)
    if live:
        args = [str(engine),'--test','--','--','--capture' if capture else '--smoke']
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    log = OUT / ('capture.log' if capture else 'smoke.log')
    with log.open('w',encoding='utf-8') as stream:
        result = subprocess.run(args,cwd=OUT,env=environment,stdout=stream,stderr=subprocess.STDOUT,
                                startupinfo=startup,timeout=90)
    text = log.read_text(encoding='utf-8',errors='replace')
    if live:
        text = (OUT / 'live/viewer.log').read_text(encoding='utf-8',errors='replace')
        log.write_text(text,encoding='utf-8')
    errors = [line for line in text.splitlines() if 'ERROR:' in line or 'SCRIPT ERROR:' in line]
    records = [line for line in text.splitlines() if 'ASSET_SMOKE ' in line]
    if result.returncode or errors or (not capture and not records):
        print(text[-6000:])
        raise SystemExit(1)
    if records:
        record = json.loads(records[-1].split('ASSET_SMOKE ',1)[1])
        (OUT / 'verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(record,ensure_ascii=False))
    else:
        print('렌더 캡처 완료')


if __name__ == '__main__':
    main()
