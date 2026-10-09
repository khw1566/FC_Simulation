"""GLB를 참조하고 접속 Marker3D·간단한 충돌·선택 조명을 저장한다."""
import json
import math

URI="res://assets/generated/harbor_assets/"


def vector(values):
    return "Vector3("+", ".join(f"{v:.8f}" for v in values)+")"


def scene(asset):
    text=f'[gd_scene load_steps={2+len(asset.collisions)} format=3]\n\n'
    text+=f'[ext_resource type="PackedScene" path="{URI}{asset.key}.glb" id="Visual"]\n\n'
    for index,shape in enumerate(asset.collisions):
        resource="BoxShape3D" if shape["type"]=="box" else "ConvexPolygonShape3D"
        text+=f'[sub_resource type="{resource}" id="Collision{index}"]\n'
        if shape["type"]=="box": text+='size = '+vector(shape["size_m"])+"\n\n"
        else:
            values=", ".join(f"{v:.8f}" for point in shape["points_m"] for v in point)
            text+=f'points = PackedVector3Array({values})\n\n'
    text+=f'[node name="{asset.key}" type="Node3D"]\nmetadata/units = "meters"\nmetadata/detail_profile = "harbor_low_poly_flat_v1"\nmetadata/anchor = "{asset.anchor}"\n'
    text+=f'\n[node name="Visual" parent="." instance=ExtResource("Visual")]\n'
    for port in asset.ports:
        text+=f'\n[node name="{port["name"]}" type="Marker3D" parent="."]\n'
        text+='position = '+vector(port["position_m"])+"\n"
        text+=f'rotation = Vector3(0, {port["rotation_y_rad"]:.8f}, 0)\n'
        text+=f'metadata/profile = "{port["profile"]}"\nmetadata/outward_direction = {vector(port["outward_direction"])}\n'
        if "width_m" in port: text+=f'metadata/width_m = {port["width_m"]}\n'
    if asset.collisions:
        text+='\n[node name="Collision" type="StaticBody3D" parent="."]\ncollision_layer = 1\ncollision_mask = 1\n'
        for i,shape in enumerate(asset.collisions):
            text+=f'\n[node name="Shape{i}" type="CollisionShape3D" parent="Collision"]\nshape = SubResource("Collision{i}")\n'
            if shape["type"]=="box": text+='position = '+vector(shape["center_m"])+"\n"
    if asset.category=="lighthouse":
        socket=next(port for port in asset.ports if port["name"]=="LightSocket")
        from .mesh import PALETTE
        color=PALETTE[asset.extra["navigation_light_color"]]
        text+='\n[node name="NavigationLight" type="OmniLight3D" parent="."]\nvisible = false\n'
        text+='position = '+vector(socket["position_m"])+"\n"
        text+=f'light_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\nlight_energy = 0.4\nshadow_enabled = false\nomni_range = 16.0\ndistance_fade_enabled = true\ndistance_fade_begin = 60.0\ndistance_fade_length = 20.0\n'
    return text


def assembly(key,example):
    instances=[(name,URI+name+".tscn",position,yaw) for name,position,yaw in example["placements"]]
    instances += [(f"External{i}",entry["scene"],entry["position_m"],entry["rotation_y_rad"]) for i,entry in enumerate(example.get("external_instances",[]))]
    unique=list(dict.fromkeys(uri for _,uri,_,_ in instances))
    text=f'[gd_scene load_steps={1+len(unique)} format=3]\n\n'
    for i,uri in enumerate(unique): text+=f'[ext_resource type="PackedScene" path="{uri}" id="Model{i}"]\n'
    text+=f'\n[node name="{key}" type="Node3D"]\nmetadata/placement_status = "synthetic_assembly"\n'
    for i,(name,uri,position,yaw) in enumerate(instances):
        text+=f'\n[node name="{name}_{i}" parent="." instance=ExtResource("Model{unique.index(uri)}")]\nposition = {vector(position)}\nrotation = Vector3(0, {yaw:.8f}, 0)\n'
    return text
