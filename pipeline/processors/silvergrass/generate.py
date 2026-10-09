"""억새 군집·억새 군락 타일·갈대 군락 3종 × 3 LOD와 원경 카드를 생성한다."""
from pathlib import Path
import json
import math
import os
import shutil
import subprocess
import tempfile
from PIL import Image, ImageDraw

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]
GODOT = ROOT / 'tools/godot/Godot_v4.3-stable_win64_console.exe'
# kind: (높이, 폭, 군집 x 위치, 잎 색, 이삭 색)
SPECS = {
    'silvergrass_clump': (1.8, 1.4, [0.0], (107, 120, 61), (219, 209, 178)),
    'silvergrass_patch': (1.9, 4.0, [-1.1, 0.9, 0.1, -1.0, 1.1], (115, 117, 61), (224, 212, 178)),
    'reed_patch': (2.4, 3.0, [-0.8, 0.7, -0.6, 0.8], (97, 112, 56), (122, 97, 82)),
}
SCRIPTS = ['silvergrass_geometry.gd', 'vegetation_batch_factory.gd']


def card(kind, path):
    height, width, xs, leaf, plume = SPECS[kind]
    image = Image.new('RGBA', (512, 512))
    draw = ImageDraw.Draw(image)
    sx, sy = 511 / width, 511 / height
    to_px = lambda x, y: ((x + width / 2) * sx, 511 - y * sy)
    for j, x in enumerate(xs):
        h = height * (1 - (j % 3) * 0.06)
        lean = 0.32 if kind == 'reed_patch' else 0.55
        for i in range(14):
            direction = (i - 6.5) / 6.5
            length = h * (0.55 + (i % 4) * 0.08)
            tip = to_px(x + direction * length * lean, length * (0.78 - lean * 0.25))
            draw.polygon([to_px(x - 0.04, 0), tip, to_px(x + 0.04, 0)], fill=leaf + (255,))
        for i in range(5):
            offset = (i - 2) * h * 0.08
            top_m = h * (0.92 + (i % 3) * 0.05)
            draw.line([to_px(x, 0), to_px(x + offset, top_m)], fill=leaf + (255,), width=3)
            draw.polygon([to_px(x + offset - 0.06, top_m), to_px(x + offset * 1.6, top_m - 0.38), to_px(x + offset + 0.06, top_m)], fill=plume + (255,))
    image.save(path)


def atomic(path, data):
    pending = path.with_name(path.name + '.silvergrass.pending')
    pending.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(pending, path)


def run_godot(stage, script, env):
    result = subprocess.run([str(GODOT), '--path', str(stage), '--rendering-method', 'gl_compatibility', '--script', 'res://' + script, '--quit-after', '90'],
                            env=env, capture_output=True, text=True, encoding='utf-8', timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR' in result.stderr or 'Assertion failed' in result.stderr:
        raise RuntimeError(result.stderr)


def main():
    source_dir = ROOT / 'godot_project/scripts/vegetation'
    shutil.copy2(SOURCE / 'silvergrass_geometry.gd', source_dir / 'silvergrass_geometry.gd')
    output = ROOT / 'godot_project/assets/generated/silvergrass'
    output.mkdir(parents=True, exist_ok=True)
    preview = ROOT / 'previews/asset_browser/silvergrass_check'
    preview.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='silvergrass_', dir=preview) as tmp:
        stage = Path(tmp)
        asset_dir = stage / 'assets/generated/silvergrass'
        asset_dir.mkdir(parents=True)
        script_dir = stage / 'scripts/vegetation'
        script_dir.mkdir(parents=True)
        for name in SCRIPTS + ['tree_geometry.gd']:
            shutil.copy2(source_dir / name, script_dir / name)
        for name in ['export_silvergrass.gd', 'capture.gd']:
            shutil.copy2(SOURCE / name, stage / name)
        for kind in SPECS:
            card(kind, asset_dir / (kind + '_card.png'))
        (stage / 'project.godot').write_text('config_version=5\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=1000\n', encoding='utf-8')
        env = os.environ.copy()
        env['APPDATA'] = str(stage / 'user_data')
        Path(env['APPDATA']).mkdir()
        for script in ['export_silvergrass.gd', 'capture.gd']:
            run_godot(stage, script, env)
        for file in asset_dir.iterdir():
            pending = output / (file.name + '.pending')
            shutil.copy2(file, pending)
            os.replace(pending, output / file.name)
        shutil.copy2(stage / 'silvergrass_preview.png', output / 'silvergrass_preview.png')
    manifest = json.loads((output / 'manifest.json').read_text(encoding='utf-8'))
    master_path = output.parent / 'manifest.json'
    master = json.loads(master_path.read_text(encoding='utf-8'))
    for key, entry in manifest['assets'].items():
        master.setdefault('assets', {})['silvergrass_' + key] = entry
    atomic(master_path, master)
    catalog = {'version': 1, 'kinds': list(SPECS), 'lod_ranges_m': [[0, 40], [40, 150], [150, 900]], 'chunk_size_m': 64,
               'batch_factory': 'res://scripts/vegetation/vegetation_batch_factory.gd', 'assets': manifest['assets']}
    atomic(output / 'catalog.json', catalog)


if __name__ == '__main__':
    main()
