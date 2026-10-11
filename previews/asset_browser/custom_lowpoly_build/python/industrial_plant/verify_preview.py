"""전용 복사본에서만 씬 연결과 연기 렌더를 짧게 확인."""

import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'previews/industrial_plant_check'


def main():
    project=OUT/'project'; project.mkdir(parents=True,exist_ok=True)
    for folder in ('assets/generated/industrial_plant','scripts/industrial_plant',
                   'assets/generated/industrial_lighting','scripts/industrial_lighting'):
        shutil.copytree(ROOT/'godot_project'/folder,project/folder,dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('*.import','*.tmp','*.lock'))
    (project/'shaders').mkdir(exist_ok=True)
    shutil.copy2(ROOT/'godot_project/shaders/industrial_plant_plume.gdshader',project/'shaders')
    shutil.copy2(ROOT/'godot_project/shaders/industrial_lamp_halo.gdshader',project/'shaders')
    (project/'project.godot').write_text('''config_version=5
[application]
config/name="플랜트 독립 확인"
run/main_scene="res://preview.tscn"
[display]
window/size/viewport_width=1440
window/size/viewport_height=1000
[rendering]
renderer/rendering_method="gl_compatibility"
environment/defaults/default_clear_color=Color(0.09, 0.11, 0.13, 1)
''',encoding='utf-8')
    (project/'preview.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://preview.gd" id="1"]
[node name="Preview" type="Node3D"]
script = ExtResource("1")
''',encoding='utf-8')
    (project/'preview.gd').write_text('''extends Node3D

func _ready() -> void:
	var demo = load("res://assets/generated/industrial_plant/plant_assembly_demo.tscn").instantiate()
	add_child(demo)
	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(150, 125, 180)
	camera.fov = 55
	camera.look_at(Vector3(0, 45, 0))
	camera.current = true
	var light = DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.7
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var connector = load("res://scripts/industrial_plant/plant_connector.gd")
	var moving = load("res://assets/generated/industrial_plant/rack_elbow.tscn").instantiate()
	add_child(moving)
	moving.position = Vector3(20, 0, 20)
	var source = moving.get_node("PipeConnector0")
	var target = demo.get_node("rack_straight_0/PipeConnector1")
	assert(connector.snap(moving, source, target))
	assert(source.global_position.distance_to(target.global_position) < 0.001)
	assert((-source.global_basis.z).dot(-target.global_basis.z) < -0.999)
	moving.free()
	var count := 0
	for path in ["stack_concrete", "stack_steel", "stack_triple", "flare_lattice", "process_column", "scrubber_tower", "rack_straight", "rack_elbow", "rack_tee", "rack_cross", "rack_riser", "rack_double", "smoke_gray", "steam_white", "smoke_dark"]:
		assert(load("res://assets/generated/industrial_plant/" + path + ".tscn") != null)
		count += 1
	print("PLANT_STRUCTURE_OK scenes=", count, " snap_position_and_direction=true")
	await get_tree().create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../capture.png")
	print("PLANT_CAPTURE_OK")
	get_tree().quit()
''',encoding='utf-8')
    env=dict(os.environ,APPDATA=str(OUT/'environment/roaming'),LOCALAPPDATA=str(OUT/'environment/local'))
    engine=ROOT/'tools/godot/Godot_v4.3-stable_win64.exe'
    startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=0
    for name,args in [('import',['--headless','--editor','--import']),
                      ('render',['--position','-2000,-2000','--resolution','1440x1000'])]:
        with (OUT/f'{name}.log').open('w',encoding='utf-8') as stream:
            run=subprocess.run([str(engine),'--path',str(project),*args],env=env,stdout=stream,
                               stderr=subprocess.STDOUT,startupinfo=startup,timeout=60)
        log=(OUT/f'{name}.log').read_text(encoding='utf-8',errors='replace')
        if run.returncode or 'ERROR:' in log:
            print(log[-6000:]); raise SystemExit(1)
    print(json.dumps({'isolated_import':True,'scenes':15,'snap_verified':True,'capture':str(OUT/'capture.png')}))


if __name__=='__main__': main()
