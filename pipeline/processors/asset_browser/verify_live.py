"""분리된 소형 원본으로 추가, 수정, 삭제, 프리뷰 갱신 및 쓰기 격리를 확인한다."""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'previews/asset_browser'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from vessels.mesh import VesselMesh
from PIL import Image


def main():
    fixture = OUT / 'live' / ('check_'+str(time.time_ns()))
    source = fixture / 'source'
    cache = fixture / 'cache'
    (source / 'assets').mkdir(parents=True)
    cache.mkdir()
    base = OUT / 'project'
    for folder in ['scripts','scenes']:
        shutil.copytree(base / folder,cache / folder)
    for file in ['project.godot','font.ttf','font.ttf.import']:
        shutil.copyfile(base / file,cache / file)
    (cache / '.godot').mkdir()
    shutil.copyfile(base / '.godot/global_script_class_cache.cfg',cache / '.godot/global_script_class_cache.cfg')
    shutil.copytree(base / '.godot/imported',cache / '.godot/imported')
    (cache / 'catalog.json').write_text('{"entries":[]}',encoding='utf-8')
    settings = fixture / 'settings.json'
    settings.write_text(json.dumps({'source_project':str(source),'cache_project':str(cache)}),encoding='utf-8')

    def box(width):
        (source / 'assets/box.tscn').write_text('''[gd_scene load_steps=2 format=3]
[sub_resource type="BoxMesh" id="Box"]
size = Vector3(%s,3,4)
[node name="Box" type="Node3D"]
[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("Box")
''' % width,encoding='utf-8')

    box(2)
    Image.new('RGB',(1,1),(255,0,0)).save(source / 'assets/pixel.png')
    mesh = VesselMesh()
    mesh.box((0,1,0),(2,2,2),'white')
    mesh.export(source / 'assets/model.glb','LiveTest')
    (source / 'assets/data.json').write_text('{"value":1}',encoding='utf-8')

    def fingerprints():
        return {str(file.relative_to(source)):hashlib.sha256(file.read_bytes()).hexdigest()
                for file in source.rglob('*') if file.is_file()}

    def sync():
        before = fingerprints()
        subprocess.run([str(OUT / 'AssetPreview.exe'),'--test','--settings',str(settings),'--sync-once'],check=True,timeout=90)
        assert before == fingerprints(), '원본 파일이 변경되었습니다.'
        assert not (source / '.godot').exists()
        assert not list(source.rglob('*.import'))
        state = json.loads((cache / 'live_status.json').read_text(encoding='utf-8'))
        assert state['state']=='ready',state

    sync()
    paths = [entry['path'] for entry in json.loads((cache / 'catalog.json').read_text(encoding='utf-8'))['entries']]
    assert 'res://assets/model.glb' in paths and 'res://assets/pixel.png' in paths
    assert (cache / 'assets/model.glb.import').exists()

    probe = '''extends SceneTree
var browser: Control
var stage := 0
var ticks := 0
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    browser = load("res://scenes/browser.tscn").instantiate()
    root.add_child(browser)
    print("LIVE_UI_READY")
    var timer := Timer.new()
    timer.wait_time = 0.2
    timer.timeout.connect(check)
    root.add_child(timer)
    timer.start()
func check() -> void:
    ticks += 1
    if ticks > 300:
        print("LIVE_UI_TIMEOUT")
        quit(1)
    if stage == 0 and browser.preview.model != null and is_equal_approx(browser.preview.bounds.size.x,7.0):
        var added := false
        for entry in browser.entries:
            added = added or str(entry.path)=="res://assets/new_data.json"
        var texture: Texture2D = ResourceLoader.load("res://assets/pixel.png", "Texture2D", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
        if not added or texture.get_width()!=2 or texture.get_image().get_pixel(0,0).g<0.9:
            return
        print("LIVE_UI_UPDATED")
        stage = 1
    elif stage == 1:
        for entry in browser.entries:
            if str(entry.path)=="res://assets/box.tscn":
                return
        print("LIVE_UI_DELETED")
        quit(0)
'''
    (cache / 'probe.gd').write_text(probe,encoding='utf-8')
    environment = dict(os.environ)
    environment['APPDATA'] = str(fixture / 'environment/roaming')
    environment['LOCALAPPDATA'] = str(fixture / 'environment/local')
    Path(environment['APPDATA']).mkdir(parents=True)
    Path(environment['LOCALAPPDATA']).mkdir(parents=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    log_path = fixture / 'ui.log'
    with log_path.open('w',encoding='utf-8') as log:
        viewer = subprocess.Popen([str(OUT / 'runtime/PreviewEngine.exe'),'--path',str(cache),
                                   '--position','-2000,-2000','--script','res://probe.gd'],
                                  env=environment,stdout=log,stderr=subprocess.STDOUT,startupinfo=startup)
        def wait_for(message):
            deadline = time.monotonic()+35
            while time.monotonic()<deadline:
                output = log_path.read_text(encoding='utf-8',errors='replace')
                if 'ERROR:' in output or 'SCRIPT ERROR:' in output:
                    raise AssertionError(output[-5000:])
                if message in output:
                    return
                if viewer.poll() is not None:
                    raise AssertionError(output[-5000:])
                time.sleep(0.2)
            raise AssertionError('프리뷰 갱신 대기 시간 초과')
        try:
            wait_for('LIVE_UI_READY')
            box(7)
            Image.new('RGB',(2,2),(0,255,0)).save(source / 'assets/pixel.png')
            (source / 'assets/new_data.json').write_text('{"added":true}',encoding='utf-8')
            sync()
            wait_for('LIVE_UI_UPDATED')
            (source / 'assets/box.tscn').unlink()
            sync()
            wait_for('LIVE_UI_DELETED')
            assert viewer.wait(timeout=10)==0
        finally:
            if viewer.poll() is None:
                viewer.kill()
                viewer.wait()
    report = {'addition':True,'selected_scene_reload':True,'texture_reload':True,
              'deletion':True,'source_unchanged':True,'source_import_cache_created':False,
              'fixture':str(fixture)}
    (OUT / 'live_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))


if __name__ == '__main__':
    main()
