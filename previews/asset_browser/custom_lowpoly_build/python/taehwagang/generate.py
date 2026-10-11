"""태화강역 전용 GLB·씬·자산 인덱스를 재생성한다."""

import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from taehwagang import station, rail_yard, forecourt, district
from taehwagang.geometry import StationMesh
from taehwagang.preview import render

OUTPUT = ROOT / 'godot_project/assets/generated/taehwagang'
PARTS = {'station':station, 'rail_yard':rail_yard, 'forecourt':forecourt, 'district':district}


def validate(mesh, model):
    data = model.read_bytes()
    assert struct.unpack_from('<III',data) == (0x46546C67,2,len(data))
    size,kind = struct.unpack_from('<II',data,12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20+size])
    binary_length = struct.unpack_from('<I',data,20+size)[0]
    assert binary_length == doc['buffers'][0]['byteLength']
    for view in doc['bufferViews']:
        assert view['byteOffset']+view['byteLength'] <= binary_length
    count = sum(doc['accessors'][p['attributes']['POSITION']]['count']//3
                for p in doc['meshes'][0]['primitives'])
    assert count == len(mesh.faces)
    for face in mesh.faces:
        assert all(math.isfinite(v) for p in face[:3] for v in p)
        assert abs(sum(n*n for n in face[3])-1) < 1e-6
    return count


def record(path, mesh):
    points = [p for f in mesh.faces for p in f[:3]]
    lo = [min(p[k] for p in points) for k in range(3)]
    hi = [max(p[k] for p in points) for k in range(3)]
    return {'file_path':'res://assets/generated/taehwagang/'+path.name,
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'size_bytes':path.stat().st_size,'type':'station_district_model',
            'metadata':{'bbox':None,'elevation_min':lo[1],'elevation_max':hi[1],
                        'resolution':{'type':'triangle_mesh','triangles':len(mesh.faces)},
                        'aabb_min_m':lo,'aabb_max_m':hi,'units':'meters',
                        'georeferenced':False,'surveyed':False}}


def main():
    config = json.loads((ROOT/'config/taehwagang_asset.json').read_text(encoding='utf-8'))
    OUTPUT.mkdir(parents=True,exist_ok=True)
    meshes = {key:module.build(config) for key,module in PARTS.items()}
    complete = StationMesh()
    for mesh in meshes.values():
        complete.faces.extend(mesh.faces)
    meshes['taehwagang_complete'] = complete
    assets, checks = {}, {}
    for key,mesh in meshes.items():
        model = OUTPUT/f'{key}.glb'
        mesh.export(model,key)
        checks[key] = validate(mesh,model)
        assets[key] = record(model,mesh)
        scene = OUTPUT/f'{key}.tscn'
        scene.write_text(f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/generated/taehwagang/{key}.glb" id="1"]

[node name="{key}" type="Node3D"]
metadata/units = "meters"
metadata/surveyed = false
metadata/georeferenced = false
metadata/front_axis = "+Z"

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="GroundOrigin" type="Marker3D" parent="."]
''',encoding='utf-8')
        assets[key+'_scene'] = record(scene,mesh)
        assets[key+'_scene']['type'] = 'packed_scene'
        if key in ('station','taehwagang_complete'):
            with scene.open('a',encoding='utf-8') as stream:
                stream.write('''
[node name="StationName" type="Label3D" parent="."]
position = Vector3(0, 16.5, 21.5)
text = "태화강역"
font_size = 96
pixel_size = 0.012
modulate = Color(1, 1, 1, 1)
outline_modulate = Color(0, 0, 0, 1)
''')
            assets[key+'_scene'] = record(scene,mesh)
            assets[key+'_scene']['type'] = 'packed_scene'
    render(complete,OUTPUT/'district_preview.png','태화강역 / 역사와 역전 구역')
    render(meshes['station'],OUTPUT/'station_preview.png','태화강역 / 신축 역사 외관')
    for key,mesh in (('district_preview',complete),('station_preview',meshes['station'])):
        assets[key] = record(OUTPUT/f'{key}.png',mesh)
        assets[key]['type'] = 'preview_image'
        assets[key]['metadata']['resolution'] = {'width_px':1600,'height_px':1050}
    manifest = {'version':1,'name_ko':config['name_ko'],'basis_ko':config['basis_ko'],
                'sources':config['sources'],'assets':assets}
    (OUTPUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    # 공용 인덱스는 마지막에 새로 읽고 변경 감지 후 필요한 항목만 병합한다.
    merge_index(OUTPUT.parent/'manifest.json','assets',{'taehwagang_'+k:v for k,v in assets.items()})
    modules = []
    for path in sorted(Path(__file__).parent.glob('*.py')):
        modules.append({'path':path.relative_to(ROOT).as_posix(),
                        'lines':len(path.read_text(encoding='utf-8').splitlines()),
                        'responsibility':path.read_text(encoding='utf-8').splitlines()[0].strip('"')})
    for relative,description in (
        ('godot_project/scripts/core/taehwagang_asset_preview.gd','태화강역 독립 선택 프리뷰'),
        ('godot_project/scenes/taehwagang_asset_preview.tscn','태화강역 프리뷰 진입 씬')):
        path = ROOT/relative
        modules.append({'path':relative,'lines':len(path.read_text(encoding='utf-8').splitlines()),
                        'responsibility':description})
    for index in (ROOT/'module_index.json',ROOT/'godot_project/module_index.json'):
        document = json.loads(index.read_text(encoding='utf-8'))
        section = next(key for key in document if key != 'metadata' and isinstance(document[key],dict))
        merge_index(index,section,{'taehwagang_assets':{'description':'태화강역 및 역전 구역 독립 에셋','modules':modules}})
    (ROOT/'results/261004_TaehwagangValidation.json').write_text(
        json.dumps({'glb_valid':True,'finite_positions':True,'unit_normals':True,
                    'triangles':checks},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(checks))


def merge_index(path, section, updates):
    before = path.read_bytes() if path.exists() else b'{}'
    document = json.loads(before)
    document.setdefault(section,{}).update(updates)
    if path.exists() and path.read_bytes() != before:
        raise RuntimeError(f'동시 변경 감지: {path}. 재실행하여 최신 내용에 병합하세요.')
    path.write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')


if __name__ == '__main__':
    main()
