"""지도 전체를 실행하지 않는 2D 벡터 표시 확인."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
ENGINE=ROOT/'tools/godot/Godot_v4.3-stable_win64.exe'


def main():
    config=json.loads((ROOT/'config/simple_vector_maps.json').read_text(encoding='utf-8'))
    records=[]
    for meta_path in sorted((ROOT/'godot_project/assets/maps').glob('*/map_meta.json')):
        meta=json.loads(meta_path.read_text(encoding='utf-8'))
        folder=(ROOT/'godot_project'/meta['assets']['tactical_map'][6:]).parent
        root=ET.parse(folder/'map.svg').getroot()
        n=config['canvas_size']
        assert root.attrib['viewBox']==f'0 0 {n} {n}'
        masks=list((folder/'masks').glob('*.svg'))
        tiles=config['tile_grid']**2
        assert len(masks)==10 and len(list((folder/'tiles').glob('*.svg')))==tiles
        records.append({'map_id':meta['id'],'svg_layers':len(masks),'tiles':tiles})
    with tempfile.TemporaryDirectory(prefix='simple_map_check_',dir=ROOT/'results') as temporary:
        project=Path(temporary)
        pending=['scripts/views/map_hud_view.gd','scripts/services/vector_map_display.gd']
        seen=set()
        while pending:
            relative=pending.pop()
            if relative in seen: continue
            seen.add(relative)
            source=ROOT/'godot_project'/relative
            text=source.read_text(encoding='utf-8')
            target=project/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_text(text,encoding='utf-8')
            pending.extend(p for p in re.findall(r'res://([^"\s]+\.gd)',text) if p not in seen)
        key='ulsan_metro_80km'
        meta=json.loads((ROOT/f'godot_project/assets/maps/{key}/map_meta.json').read_text(encoding='utf-8'))
        source=ROOT/'godot_project'/meta['assets']['tactical_map'][6:]
        shutil.copytree(source.parent,project/'vector')
        (project/'project.godot').write_text('''config_version=5
[application]
config/name="수동 벡터 지도 표시 확인"
[display]
window/size/viewport_width=1280
window/size/viewport_height=800
[rendering]
renderer/rendering_method="gl_compatibility"
''',encoding='utf-8')
        (project/'check.gd').write_text('''extends SceneTree

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var hud = load("res://scripts/views/map_hud_view.gd")
    if hud == null:
        quit(1)
        return
    var background := ColorRect.new()
    background.color = Color(0.05, 0.05, 0.05)
    background.size = Vector2(1280, 800)
    root.add_child(background)
    var image := Image.new()
    if image.load_svg_from_string(FileAccess.get_file_as_string("res://vector/map.svg")) != OK:
        quit(1)
        return
    var overview := TextureRect.new()
    overview.texture = ImageTexture.create_from_image(image)
    overview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    overview.position = Vector2(20, 65)
    overview.size = Vector2(710, 710)
    root.add_child(overview)
    var frame := Control.new()
    frame.clip_contents = true
    frame.position = Vector2(780, 65)
    frame.size = Vector2(460, 460)
    root.add_child(frame)
    var detail := TextureRect.new()
    detail.texture = overview.texture
    detail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    detail.size = frame.size * 80.0
    detail.position = frame.size * 0.5 - Vector2(0.61, 0.51) * detail.size
    frame.add_child(detail)
    var layer = load("res://scripts/views/vector_map_tiles.gd").new()
    detail.add_child(layer)
    if not layer.configure("res://vector/tiles.json", frame):
        quit(1)
        return
    var label := Label.new()
    label.position = Vector2(20, 20)
    label.text = "전체 지도 SVG / 오른쪽: 1km 범위 벡터 미니맵"
    root.add_child(label)
    for i in range(45):
        await process_frame
    if layer.cache.is_empty() or layer.cache_bytes > layer.MAX_CACHE_BYTES:
        push_error("벡터 타일 로딩 또는 캐시 크기 실패")
        quit(1)
        return
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://display.png")
    detail.position -= Vector2(80, 80)
    for i in range(15):
        await process_frame
    print("SIMPLE_MAP_PASS layers=10 tiles=256 svg_viewport=1 cache_bytes=", layer.cache_bytes)
    background.free()
    overview.free()
    frame.free()
    label.free()
    quit(0)
''',encoding='utf-8')
        environment=os.environ.copy()
        environment['APPDATA']=str(project/'appdata')
        (project/'appdata/Godot').mkdir(parents=True,exist_ok=True)
        # 클래스 색인과 코드 파싱만 임시 프로젝트에서 준비한다.
        logs=[]
        for arguments in (['--headless','--editor','--quit'],
                          ['--rendering-method','gl_compatibility','--position','-32000,-32000','--script','res://check.gd']):
            result=subprocess.run([str(ENGINE),'--path',str(project),*arguments],capture_output=True,
                                  text=True,encoding='utf-8',errors='replace',env=environment,
                                  timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
            log=result.stdout+result.stderr
            logs.append(log)
            errors=[line for line in log.splitlines() if 'ERROR:' in line and not line.startswith('ERROR: Safe save failed.')]
            if result.returncode or errors:
                (ROOT/'results/261004_SimpleMapDisplay.log').write_text('\n'.join(logs),encoding='utf-8')
                raise RuntimeError(log)
        assert 'SIMPLE_MAP_PASS' in logs[-1]
        shutil.copyfile(project/'display.png',ROOT/'results/261004_SimpleMapDisplay.png')
        (ROOT/'results/261004_SimpleMapDisplay.log').write_text('\n'.join(logs),encoding='utf-8')
    (ROOT/'results/261004_SimpleMapCheck.json').write_text(json.dumps(
        {'maps':records,'display':'PASS','full_world_started':False},ensure_ascii=False,indent=2),encoding='utf-8')
    print('SIMPLE_MAP_PASS maps=6 vector_display=PASS')


if __name__=='__main__':
    main()
