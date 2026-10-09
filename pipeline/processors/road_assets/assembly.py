"""씬의 연결 Marker3D와 게임에 연결하지 않는 혼합 조립 예제."""
import math

URI="res://assets/generated/road_assets/"


def model_scene(key, ports, overlay=None):
    extra=f'[ext_resource type="PackedScene" path="{URI}{overlay}.glb" id="2"]\n' if overlay else ''
    text=f'''[gd_scene load_steps={3 if overlay else 2} format=3]

[ext_resource type="PackedScene" path="{URI}{key}.glb" id="1"]
{extra}
[node name="{key}" type="Node3D"]
metadata/asset_type = "{key}"
metadata/procedural = true
metadata/units = "meters"
metadata/runtime_applied = false

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="GroundOrigin" type="Marker3D" parent="."]
'''
    if overlay:
        text+=f'\n[node name="RoadMarkings" parent="." instance=ExtResource("2")]\n'
    for p in ports:
        x,y,z=p["position_m"]; dx,dy,dz=p["outward_direction"]
        angle=math.atan2(-dx,-dz); cross=p["profile"]
        text+=f'''
[node name="{p['name']}" type="Marker3D" parent="."]
position = Vector3({x}, {y}, {z})
rotation = Vector3(0, {angle}, 0)
metadata/profile = "{cross['id']}"
metadata/width_m = {cross['width_m']}
metadata/surface_y_m = {cross['surface_y_m']}
metadata/lane_count = {cross['lane_count']}
'''
    return text


def example():
    placements=[]
    def add(key,p,angle=0): placements.append({"asset":key,"position_m":p,"rotation_y":angle})
    # 차도·서로 다른 보도·교차로·경계 부재를 별개로 조립한다.
    for i in range(3): add("road_urban_2l_straight",[0,0,i*12])
    styles=("paver_gray","wood_cross","stone_large")
    for side in (-1,1):
        for i,style in enumerate(styles):
            add(f"walk_{style}_w3_straight",[side*5.45,0,i*12])
            add("addon_curb_straight",[side*3.85,0,i*12])
        add("addon_planter_strip",[side*7.90,0,12])
    add("mark_zebra_crossing",[0,0,12])
    add("addon_tactile_warning",[5.45,.15,10])
    add("walk_concrete_w3_curve90",[5.45,0,36])
    add("walk_concrete_w3_tee",[22,0,12])
    add("walk_gravel_w3_straight",[22,0,25.5])
    add("walk_earth_w3_straight",[22,0,37.5])
    add("walk_width_1.5_to_3",[22,0,49.5],math.pi)
    add("walk_forest_w1.5_straight",[22,0,61.5])
    add("walk_curb_ramp_w3",[22,0,-1.5])
    add("addon_railing",[24,0,25.5])
    unique=list(dict.fromkeys(p["asset"] for p in placements))
    text=f'[gd_scene load_steps={len(unique)+1} format=3]\n\n'
    for i,key in enumerate(unique): text+=f'[ext_resource type="PackedScene" path="{URI}{key}.tscn" id="{i+1}"]\n'
    text+='\n[node name="RoadWalkMixDemo" type="Node3D"]\nmetadata/runtime_applied = false\n'
    for i,p in enumerate(placements):
        text+=f'''
[node name="Part{i}_{p['asset']}" parent="." instance=ExtResource("{unique.index(p['asset'])+1}")]
position = Vector3({', '.join(map(str,p['position_m']))})
rotation = Vector3(0, {p['rotation_y']}, 0)
'''
    return text,placements
