"""공통 숲 수목 12형태(활엽 낙엽수·소나무형·관목·대나무 각 3) × 3 LOD를 생성한다.

원본 Godot 프로젝트의 임포터·에디터를 실행하지 않고 프리뷰 전용 임시 프로젝트에서 씬을 저장한 뒤 복사한다.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]
GODOT = ROOT / 'tools/godot/Godot_v4.3-stable_win64_console.exe'
KINDS = ['deciduous_a', 'deciduous_b', 'deciduous_c', 'pine_a', 'pine_b', 'pine_c',
         'shrub_a', 'shrub_b', 'shrub_c', 'bamboo_a', 'bamboo_b', 'bamboo_c']
LOD_RANGES = [[0, 100], [100, 350], [350, 1500]]
SCRIPTS = ['forest_tree_geometry.gd', 'vegetation_batch_factory.gd']


def atomic(path, data):
    pending = path.with_name(path.name + '.forest.pending')
    pending.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(pending, path)


def run_godot(stage, script, env):
    result = subprocess.run([str(GODOT), '--path', str(stage), '--rendering-method', 'gl_compatibility', '--script', 'res://' + script, '--quit-after', '120'],
                            env=env, capture_output=True, text=True, encoding='utf-8', timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR' in result.stderr or 'Assertion failed' in result.stderr:
        raise RuntimeError(result.stderr)


def main():
    source_dir = ROOT / 'godot_project/scripts/vegetation'
    shutil.copy2(SOURCE / 'forest_tree_geometry.gd', source_dir / 'forest_tree_geometry.gd')
    output = ROOT / 'godot_project/assets/generated/forest_trees'
    output.mkdir(parents=True, exist_ok=True)
    preview = ROOT / 'previews/asset_browser/forest_trees_check'
    preview.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='forest_', dir=preview) as tmp:
        stage = Path(tmp)
        asset_dir = stage / 'assets/generated/forest_trees'
        asset_dir.mkdir(parents=True)
        script_dir = stage / 'scripts/vegetation'
        script_dir.mkdir(parents=True)
        for name in SCRIPTS:
            shutil.copy2(source_dir / name, script_dir / name)
        for name in ['export_forest_trees.gd', 'capture.gd']:
            shutil.copy2(SOURCE / name, stage / name)
        (stage / 'project.godot').write_text('config_version=5\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=1000\n', encoding='utf-8')
        env = os.environ.copy()
        env['APPDATA'] = str(stage / 'user_data')
        Path(env['APPDATA']).mkdir()
        for script in ['export_forest_trees.gd', 'capture.gd']:
            run_godot(stage, script, env)
        for file in asset_dir.iterdir():
            pending = output / (file.name + '.pending')
            shutil.copy2(file, pending)
            os.replace(pending, output / file.name)
        shutil.copy2(stage / 'forest_trees_preview.png', output / 'forest_trees_preview.png')
    manifest = json.loads((output / 'manifest.json').read_text(encoding='utf-8'))
    master_path = output.parent / 'manifest.json'
    master = json.loads(master_path.read_text(encoding='utf-8'))
    for key, entry in manifest['assets'].items():
        master.setdefault('assets', {})['forest_trees_' + key] = entry
    atomic(master_path, master)
    catalog = {'version': 1, 'kinds': KINDS, 'species': {'deciduous': KINDS[0:3], 'pine': KINDS[3:6], 'shrub': KINDS[6:9], 'bamboo': KINDS[9:12]},
               'lod_ranges_m': LOD_RANGES, 'chunk_size_m': 64, 'sway_weight': 'vertex_color_alpha',
               'batch_factory': 'res://scripts/vegetation/vegetation_batch_factory.gd', 'assets': manifest['assets']}
    atomic(output / 'catalog.json', catalog)
    for kind in KINDS:
        tris = [manifest['assets'][f'{kind}_lod{lod}']['metadata']['triangles'] for lod in range(3)]
        print(kind, tris)


if __name__ == '__main__':
    main()
