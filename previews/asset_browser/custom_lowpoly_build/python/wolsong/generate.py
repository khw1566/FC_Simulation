"""공유 파일을 수정하지 않고 월성 전용 에셋을 생성하고 검증한다."""

import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from wolsong.design import build_complex
from wolsong.preview import render

OUTPUT = ROOT / "godot_project/assets/generated/wolsong"


def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    mesh = build_complex()
    model = OUTPUT / "wolsong_npp.glb"
    mesh.export(model,"WolsongNuclearPowerPlant")
    scene = OUTPUT / "wolsong_npp.tscn"
    scene.write_text('''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/generated/wolsong/wolsong_npp.glb" id="1"]

[node name="WolsongNuclearPowerPlant" type="Node3D"]
metadata/units = "meters"
metadata/surveyed = false
metadata/reactor_count = 4

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="GroundOrigin" type="Marker3D" parent="."]
''',encoding="utf-8")
    points = [p for f in mesh.faces for p in f[:3]]
    lo = [min(p[k] for p in points) for k in range(3)]
    hi = [max(p[k] for p in points) for k in range(3)]
    assets = {}
    for path in (model,scene):
        assets[path.stem + '_' + path.suffix[1:]] = {
            "file_path":"res://assets/generated/wolsong/"+path.name,
            "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "size_bytes":path.stat().st_size,"bbox":None,
            "min_elevation":lo[1],"max_elevation":hi[1],
            "resolution":{"type":"triangle_mesh","triangles":len(mesh.faces)},
            "aabb_min_m":lo,"aabb_max_m":hi,"surveyed":False}
    manifest = {"version":1,"name_ko":"월성 원자력발전소 1~4호기 외관 에셋",
                "units":"meters","up_axis":"Y","georeferenced":False,
                "basis":"공개 시설 소개 참고, 치수와 로컬 배치는 예술적 근사",
                "sources":["https://cms.khnp.co.kr/eng/contents.do?key=2001"],
                "assets":assets}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    render(mesh,OUTPUT / "preview.png")
    # GLB 컨테이너와 모든 위치/법선 접근자의 유효 범위를 검사한다.
    data = model.read_bytes()
    magic,version,length = struct.unpack_from('<III',data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    count,kind = struct.unpack_from('<II',data,12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20+count])
    for view in doc['bufferViews']:
        assert view['byteOffset']+view['byteLength'] <= doc['buffers'][0]['byteLength']
    assert sum(doc['accessors'][p['attributes']['POSITION']]['count']//3
               for p in doc['meshes'][0]['primitives']) == len(mesh.faces)
    for f in mesh.faces:
        assert abs(sum(n*n for n in f[3])-1) < 1e-6
    print(json.dumps({"triangles":len(mesh.faces),"bounds":[lo,hi],"glb_valid":True}))


if __name__ == "__main__":
    main()
