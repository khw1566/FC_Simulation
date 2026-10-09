"""혼합 교차로와 기존 보행로·데크를 연결하는 독립 조립 예제."""
import math
from road_assets.assembly import URI
from road_assets.junctions import width


def junction_parts(main,branch,shape):
    items=[{"asset":f"mix_junction_{main}l_{branch}l_{shape}_core","position_m":[0,0,0],"rotation_y":0},
           {"asset":f"mix_junction_{main}l_{branch}l_{shape}_crossings","position_m":[0,0,0],"rotation_y":0}]
    for name,(dx,dz) in {"North":(0,-1),"South":(0,1),"East":(1,0),"West":(-1,0)}.items():
        if name=="West" and shape=="tee": continue
        lanes=branch if dx else main
        distance=width(main if dx else branch)/2+3
        for suffix in (("concrete" if dx else "asphalt"),"markings"):
            items.append({"asset":f"mix_approach_{lanes}l_{suffix}","position_m":[dx*distance,0,dz*distance],
                          "rotation_y":math.pi/2 if dx else 0})
    return items


def placements():
    items=[]
    def add(key,x,y,z,a=0): items.append({"asset":key,"position_m":[x,y,z],"rotation_y":a})
    add("mix_junction_4l_2l_cross_core",0,0,0)
    # 교차로 중심의 포트와 진입부의 끝을 맞춘다.
    for side in (-1,1):
        add("mix_approach_4l_asphalt",0,0,side*(width(2)/2+3))
        add("road_urban_4l_straight",0,0,side*(width(2)/2+12))
        add("mix_approach_2l_concrete",side*(width(4)/2+3),0,0,math.pi/2)
        add("road_concrete_2l_straight",side*(width(4)/2+12),0,0,math.pi/2)
    add("mix_junction_4l_2l_cross_crossings",0,0,0)
    # 광장 네 방향에 기존 보행로, 목재 데크, 곡선, 높이 전환을 연결한다.
    add("deck_stone_plaza_6m",40,0,0)
    add("walk_paver_gray_w3_straight",31,0,0,math.pi/2)
    add("deck_wood_long_w3_straight",40,0,-9)
    add("deck_weathered_w3_straight",40,0,9)
    add("deck_ramp_w3_rise1m",40,0,21)
    add("walk_stone_large_w3_straight",40,1,33)
    add("deck_wood_cross_w3_curve90",49,0,0,math.pi/2)
    add("walk_concrete_w3_straight",55,0,-18)
    for side in (-1,1):
        for z in (-12,-6): add("deck_rail_wood_6m",40+side*1.44,.15,z)
        for z in (6,12): add("deck_rail_cable_6m",40+side*1.44,.15,z)
        add("deck_rail_cable_rise1m",40+side*1.44,.15,21)
        side_name="left" if side<0 else "right"
        add(f"deck_rail_steel_w3_curve90_{side_name}",49,.15,0,math.pi/2)
    for z in (-12,-6,6,12): add("deck_support_w3_h1.5",40,-.20,z)
    for side in (-1,1):
        for corner in (-1,1):
            add("deck_rail_steel_1.5m",40+corner*2.25,.15,side*2.94,math.pi/2)
            add("deck_rail_steel_1.5m",40+side*2.94,.15,corner*2.25)
    for z in (-2,2): add("deck_support_w4.5_h1.5",40,-.20,z)
    for p in items:
        if p["asset"].startswith(("deck_","walk_")): p["position_m"][0]+=12
    add("walk_curb_ramp_w3",31,0,0,math.pi/2)
    return items


def scene(items):
    unique=list(dict.fromkeys(p["asset"] for p in items))
    text=f'[gd_scene load_steps={len(unique)+1} format=3]\n\n'
    for i,key in enumerate(unique): text+=f'[ext_resource type="PackedScene" path="{URI}{key}.tscn" id="{i+1}"]\n'
    text+='\n[node name="MixedIntersectionDeckDemo" type="Node3D"]\nmetadata/runtime_applied = false\n'
    for i,p in enumerate(items):
        text+=f'''
[node name="Part{i}_{p['asset']}" parent="." instance=ExtResource("{unique.index(p['asset'])+1}")]
position = Vector3({', '.join(map(str,p['position_m']))})
rotation = Vector3(0, {p['rotation_y']}, 0)
'''
    return text
