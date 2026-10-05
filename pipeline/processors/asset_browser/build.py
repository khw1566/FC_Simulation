"""게임 파일을 수정하지 않는 에셋 스냅샷 및 실행파일 패키징."""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'godot_project'
OUT = ROOT / 'previews/asset_browser'
PROJECT = OUT / 'project'
ENGINE = ROOT / 'tools/godot/Godot_v4.3-stable_win64.exe'


def copy_stable(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        before = source.stat()
        shutil.copyfile(source, destination)
        after = source.stat()
        if (before.st_size,before.st_mtime_ns) == (after.st_size,after.st_mtime_ns):
            return
    raise RuntimeError(f'복사 중 변경된 파일: {source}')


def main():
    PROJECT.mkdir(parents=True,exist_ok=True)
    if '--package-only' in sys.argv:
        package(json.loads((PROJECT / 'catalog.json').read_text(encoding='utf-8')))
        return
    entries = []
    for source in sorted((GAME / 'assets').rglob('*')):
        if not source.is_file() or source.suffix == '.import':
            continue
        relative = source.relative_to(GAME)
        destination = PROJECT / relative
        copy_stable(source,destination)
        kind = ('3D' if source.suffix in ('.scn','.tscn','.glb','.gltf','.obj') else
                '이미지' if source.suffix in ('.png','.jpg','.jpeg','.svg','.webp') else '데이터')
        entries.append({'name':source.stem,'path':'res://'+relative.as_posix(),
                        'kind':kind,'size':destination.stat().st_size})
    for source in sorted((GAME / 'shaders').rglob('*')):
        if source.is_file():
            relative = source.relative_to(GAME)
            copy_stable(source,PROJECT / relative)
            entries.append({'name':source.stem,'path':'res://'+relative.as_posix(),
                            'kind':'셰이더','size':source.stat().st_size})
    scripts = ['railway_train_builder','railway_track_builder','railway_route',
               'building_mesh_builder','campus_building_policy','campus_architecture_builder',
               'building_courtyard_builder','campus_ground_overlay']
    pending = ['scripts/terrain/'+name+'.gd' for name in scripts]
    copied = set()
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        copied.add(relative)
        copy_stable(GAME / relative,PROJECT / relative)
        text = (GAME / relative).read_text(encoding='utf-8')
        pending.extend(match for match in re.findall(r'res://([^"\s]+\.gd)',text)
                       if match not in copied)
    copy_stable(GAME / 'scripts/views/custom_asset_preview.gd',
                PROJECT / 'scripts/views/model_preview.gd')
    # 독립 프리뷰는 상시 표시하고 게임 뷰포트의 활성화 상태에 의존하지 않는다.
    view = PROJECT / 'scripts/views/model_preview.gd'
    text = view.read_text(encoding='utf-8').replace('SubViewport.UPDATE_DISABLED','SubViewport.UPDATE_ALWAYS')
    text = text.replace('viewport.handle_input_locally = false',
                        'viewport.handle_input_locally = false\n\tviewport.transparent_bg = false')
    text = text.replace('var packed := load(path) as PackedScene',
                        'var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene')
    view.write_text(text,encoding='utf-8')
    ground = PROJECT / 'scripts/terrain/campus_ground_overlay.gd'
    ground.write_text(ground.read_text(encoding='utf-8').replace(
        'var image := Image.load_from_file(path)',
        'var texture := load(path) as Texture2D\n\tvar image := texture.get_image() if texture != null else null'),encoding='utf-8')
    copy_stable(Path('C:/Windows/Fonts/malgun.ttf'),PROJECT / 'font.ttf')
    settings = json.loads((PROJECT / 'assets/generated/railway/services.json').read_text(encoding='utf-8'))
    for profile in settings['services']:
        for prefix,label in [('train','열차'),('track','철도')]:
            entries.append({'name':profile['name']+' · '+label,
                            'path':prefix+':'+profile['id'],'kind':'생성 모델','size':0})
    for key,label in [('campus','울산대학교 · 과학대 캠퍼스'),
                      ('buildings','일반 건물 · 게임 메시 생성기'),
                      ('water','간몬 수면 · 게임 셰이더')]:
        entries.append({'name':label,'path':key+':preview','kind':'생성 모델','size':0})
    catalog = {'created_at':datetime.now().isoformat(timespec='seconds'),
               'file_count':len(entries),'entries':entries}
    (PROJECT / 'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf-8')
    (PROJECT / 'project.godot').write_text('''config_version=5

[application]
config/name="전체 에셋 프리뷰"
run/main_scene="res://scenes/browser.tscn"
config/features=PackedStringArray("4.3", "GL Compatibility")

[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1440
window/size/window_height_override=900
window/stretch/mode="canvas_items"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
environment/defaults/default_clear_color=Color(0.04, 0.04, 0.04, 1)
''',encoding='utf-8')
    (PROJECT / 'export_presets.cfg').write_text('''[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.json,*.geojson,*.md,*.gdshaderinc"
exclude_filter=""
export_path="../AssetPreview.exe"
script_export_mode=1

[preset.0.options]
binary_format/architecture="x86_64"
''',encoding='utf-8')
    package(catalog)


def package(catalog):
    entries = catalog['entries']
    labels = {
        'res://assets/generated/wolsong/wolsong_npp.tscn':'월성 원자력발전소 1~4호기',
        'res://assets/generated/wolsong/wolsong_npp.glb':'월성 원자력발전소 1~4호기 · GLB',
        'res://assets/generated/airport/ulsan_airport.scn':'울산공항',
        'res://assets/generated/heritage/ulsan_waeseong.scn':'울산왜성',
        'res://assets/generated/heritage/eonyang_eupseong.scn':'언양읍성 · 영화루',
        'res://assets/generated/pedestrian_bridges/generic_pedestrian_overpass.scn':'범용 보행 육교',
        'res://assets/generated/pedestrian_bridges/gulhwa_daun_crossing.scn':'굴화리–다운동 징검다리',
        'res://assets/generated/pedestrian_bridges/seonbawi_bridge.scn':'선바위교'}
    bridge_path = PROJECT / 'assets/generated/taehwa_bridges.json'
    if bridge_path.exists():
        for bridge in json.loads(bridge_path.read_text(encoding='utf-8')).get('bridges',[]):
            labels[bridge.get('preview_scene','')] = bridge.get('name','교량')
    airport_path = PROJECT / 'assets/generated/japan_airports/placement.json'
    if airport_path.exists():
        for airport in json.loads(airport_path.read_text(encoding='utf-8')).get('airports',[]):
            labels[airport['scene_path']] = airport['name_ko']
    vessel_path = PROJECT / 'assets/generated/vessels/manifest.json'
    if vessel_path.exists():
        for asset in json.loads(vessel_path.read_text(encoding='utf-8')).get('assets',{}).values():
            label = asset.get('metadata',{}).get('label_ko','선박')
            labels[asset['file_path']] = label+' · GLB'
            labels[asset['scene_path']] = label
    for entry in entries:
        entry['name'] = labels.get(entry['path'],entry['name'])
    (PROJECT / 'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf-8')
    ground = PROJECT / 'scripts/terrain/campus_ground_overlay.gd'
    ground.write_text(ground.read_text(encoding='utf-8').replace(
        'var image := Image.load_from_file(path)',
        'var texture := load(path) as Texture2D\n\tvar image := texture.get_image() if texture != null else null'),encoding='utf-8')
    def run(args,log):
        environment = dict(os.environ)
        environment['APPDATA'] = str(OUT / 'build_environment/roaming')
        environment['LOCALAPPDATA'] = str(OUT / 'build_environment/local')
        Path(environment['APPDATA']).mkdir(parents=True,exist_ok=True)
        Path(environment['LOCALAPPDATA']).mkdir(parents=True,exist_ok=True)
        with (OUT / log).open('w',encoding='utf-8') as stream:
            result = subprocess.run([str(ENGINE), '--headless','--path',str(PROJECT),*args],
                                    stdout=stream,stderr=subprocess.STDOUT,env=environment,timeout=240)
        if result.returncode:
            raise RuntimeError(f'Godot 빌드 실패: {log}')
    run(['--editor','--import'],'import.log')
    run(['--export-pack','Windows Desktop',str(OUT / 'AssetPreview.pck')],'export.log')
    copy_stable(ENGINE,OUT / 'AssetPreview.exe')
    report = {'created_at':catalog['created_at'],'entry_count':len(entries),
              'counts':{kind:sum(e['kind']==kind for e in entries)
                        for kind in sorted({e['kind'] for e in entries})},
              'pack_bytes':(OUT / 'AssetPreview.pck').stat().st_size,
              'pack_sha256':hashlib.sha256((OUT / 'AssetPreview.pck').read_bytes()).hexdigest(),
              'original_project_modified':False}
    (OUT / 'build_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    if __package__:
        from .build_live import main as build_live
    else:
        from build_live import main as build_live
    build_live()


if __name__ == '__main__':
    main()
