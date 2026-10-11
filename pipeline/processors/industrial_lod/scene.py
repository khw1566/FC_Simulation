"""독립 LOD 씬과 원본 좌표 그대로의 연결 마커를 작성한다."""
import math


def markers(meta):
    text='\n[node name="GroundOrigin" type="Marker3D" parent="."]\n'
    ports=meta.get("pipe_connectors_m",[])
    directions=meta.get("pipe_connector_directions",[])
    for i,(position,direction) in enumerate(zip(ports,directions)):
        angle=math.atan2(-direction[0],-direction[2])
        text+=f'\n[node name="PipeConnector{i}" type="Marker3D" parent="."]\nposition = Vector3({", ".join(map(str,position))})\nrotation = Vector3(0, {angle}, 0)\n'
        text+='metadata/profile = "triple_pipe_032_spacing_110"\n'
        text+='metadata/lane_count = 3\nmetadata/diameter_m = 0.64\nmetadata/lane_spacing_m = 1.1\n'
    for i,p in enumerate(meta.get("smoke_outlets_m",[])):
        text+=f'\n[node name="SmokeOutlet{i}" type="Marker3D" parent="."]\nposition = Vector3({", ".join(map(str,p))})\n'
    return text


def static_scene(name,uri,meta):
    return f'''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="{uri}" id="1"]
[ext_resource type="Script" path="res://assets/generated/industrial_lod/far_visual.gd" id="2"]

[node name="{name}" type="Node3D"]
script = ExtResource("2")
metadata/lod_only = true
metadata/source_asset = "{meta['source_asset']}"

[node name="Visual" parent="." instance=ExtResource("1")]
''' + markers(meta)


def auto_scene(key,family,base,distances):
    return f'''[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="{base}/lod_selector.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/generated/{family}/{key}.tscn" id="2"]
[ext_resource type="PackedScene" path="{base}/{family}/{key}_lod1.tscn" id="3"]
[ext_resource type="PackedScene" path="{base}/{family}/{key}_lod2.tscn" id="4"]

[node name="{family}_{key}_AutoLOD" type="Node3D"]
script = ExtResource("1")
near_end_m = {float(distances[0])}
far_begin_m = {float(distances[1])}
cull_m = {float(distances[2])}

[node name="Near" parent="." instance=ExtResource("2")]

[node name="Far" parent="." instance=ExtResource("3")]
visible = false

[node name="VeryFar" parent="." instance=ExtResource("4")]
visible = false
'''
