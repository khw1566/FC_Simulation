"""야간 조명만 전용 복사본에서 실제 렌더·주야간 전환 확인."""

import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'previews/industrial_night'


def main():
    project=OUT/'project'; project.mkdir(parents=True,exist_ok=True)
    folders=['assets/generated/'+family for family in ('industrial','industrial_plant','industrial_lighting')]
    folders+=['scripts/industrial_lighting','scripts/industrial_plant']
    for folder in folders:
        shutil.copytree(ROOT/'godot_project'/folder,project/folder,dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('*.import','*.tmp','*.lock'))
    (project/'scripts/services').mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'godot_project/scripts/services/day_night_cycle_service.gd',project/'scripts/services')
    (project/'shaders').mkdir(exist_ok=True)
    for name in ('industrial_lamp_halo.gdshader','industrial_plant_plume.gdshader'):
        shutil.copy2(ROOT/'godot_project/shaders'/name,project/'shaders')
    shutil.copy2(Path(__file__).with_name('showcase.gd'),project/'showcase.gd')
    (project/'project.godot').write_text('''config_version=5
[application]
config/name="공단 야경 독립 확인"
run/main_scene="res://showcase.tscn"
[display]
window/size/viewport_width=1600
window/size/viewport_height=1100
[rendering]
renderer/rendering_method="gl_compatibility"
''',encoding='utf-8')
    (project/'showcase.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://showcase.gd" id="1"]
[node name="Showcase" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    env=dict(os.environ,APPDATA=str(OUT/'environment/roaming'),LOCALAPPDATA=str(OUT/'environment/local'))
    startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=0
    engine=ROOT/'tools/godot/Godot_v4.3-stable_win64.exe'
    for name,args in [('import',['--headless','--editor','--import']),
                      ('render',['--position','-2000,-2000','--resolution','1600x1100','--quit-after','1200'])]:
        with (OUT/f'{name}.log').open('w',encoding='utf-8') as stream:
            run=subprocess.run([str(engine),'--path',str(project),*args],env=env,stdout=stream,
                               stderr=subprocess.STDOUT,startupinfo=startup,timeout=60)
        log=(OUT/f'{name}.log').read_text(encoding='utf-8',errors='replace')
        if run.returncode or 'ERROR:' in log:
            print(log[-6500:]); raise SystemExit(1)
    if 'NIGHT_LIGHTING_OK' not in log or not (OUT/'night.png').exists(): raise RuntimeError('야경 확인 미완료')
    print(json.dumps({'night_render':str(OUT/'night.png'),'day_night_switch':True,'instance_isolation':True}))


if __name__=='__main__': main()
