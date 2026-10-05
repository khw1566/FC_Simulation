"""독립 선박 GLB, Godot 씬, 매니페스트와 미리보기 생성 진입점."""

import hashlib
import json
import sys
from pathlib import Path

if __package__:
    from .designs import SPECS, build_vessel
    from .preview import render_preview
    from .lighting import attach
else:
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    from vessels.designs import SPECS, build_vessel
    from vessels.preview import render_preview
    from vessels.lighting import attach

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "godot_project/assets/generated/vessels"


def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    assets = {}
    previews = []
    for kind,(label,length,beam,draft,deck) in SPECS.items():
        mesh = build_vessel(kind)
        path = OUTPUT / f"{kind}.glb"
        mesh.export(path,kind)
        points = [p for f in mesh.faces for p in f[:3]]
        minimum = [min(p[k] for p in points) for k in range(3)]
        maximum = [max(p[k] for p in points) for k in range(3)]
        metadata = {"label_ko":label,"length_m":length,"beam_m":beam,
                    "draft_m":draft,"waterline_y_m":0,"forward_axis":"-Z",
                    "units":"meters","triangles":len(mesh.faces),
                    "aabb_min_m":minimum,"aabb_max_m":maximum,
                    "bbox":None,"elevation_min":minimum[1],"elevation_max":maximum[1],
                    "resolution":None,"georeferenced":False,
                    "lighting":{"marker_count":4,"local_light_count":1,"energy":0.2,"fade_end_m":100,"glb_includes_lights":False}}
        assets[kind] = {"file_path":f"res://assets/generated/vessels/{kind}.glb",
                        "scene_path":f"res://assets/generated/vessels/{kind}.tscn",
                        "format":"GLB","type":"vessel_model","metadata":metadata,
                        "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                        "size_bytes":path.stat().st_size}
        scene = f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/generated/vessels/{kind}.glb" id="1"]

[node name="{kind}" type="Node3D"]
metadata/vessel_type = "{kind}"
metadata/length_m = {float(length)}
metadata/beam_m = {float(beam)}
metadata/waterline_y_m = 0.0
metadata/forward_axis = "-Z"

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="Bow" type="Marker3D" parent="."]
position = Vector3(0, 0, {-length/2})

[node name="Stern" type="Marker3D" parent="."]
position = Vector3(0, 0, {length/2})

[node name="Waterline" type="Marker3D" parent="."]
'''
        scene = attach(scene, length, beam, deck, kind)
        scene_path = OUTPUT / f"{kind}.tscn"
        scene_path.write_text(scene,encoding="utf-8")
        assets[kind]["scene_sha256"] = hashlib.sha256(scene_path.read_bytes()).hexdigest()
        previews.append((kind,label,length,beam,mesh))
    manifest = {"version":1,"description":"게임용 경량 해상 선박 6종", "assets":assets}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    master_path = OUTPUT.parent / "manifest.json"
    master = json.loads(master_path.read_text(encoding="utf-8")) if master_path.exists() else {"assets":{}}
    for kind,entry in assets.items():
        master.setdefault("assets",{})[f"vessel_{kind}"] = entry
    master_path.write_text(json.dumps(master,ensure_ascii=False,indent=2),encoding="utf-8")
    render_preview(previews,OUTPUT / "fleet_preview.png")
    print(json.dumps({k:v["metadata"]["triangles"] for k,v in assets.items()},ensure_ascii=False))


if __name__ == "__main__":
    main()
