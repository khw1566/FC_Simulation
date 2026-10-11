"""범용 산업 에셋과 무작위 배치용 메타데이터 생성."""

import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from industrial import factories,equipment,pipes,structures,cranes
from industrial.preview import render
from simple_maps.publish import atomic,merge
from industrial_lighting.apply import apply_family

OUTPUT=ROOT/'godot_project/assets/generated/industrial'


def main():
    config=json.loads((ROOT/'config/industrial_assets.json').read_text(encoding='utf-8'))
    OUTPUT.mkdir(parents=True,exist_ok=True)
    entries,catalog,models={},{},[]
    for key,label in config['assets'].items():
        builder=(factories if key.startswith('factory_') else pipes if key.startswith('pipeline_')
                 else cranes if key.endswith('_crane') else structures if key in
                 ('transmission_tower','cooling_tower','cooling_fan_bank','shipbuilding_hangar') else equipment)
        mesh=builder.build(key)
        model=OUTPUT/f'{key}.glb'
        mesh.export(model,key)
        data=model.read_bytes()
        if struct.unpack_from('<III',data)!=(0x46546C67,2,len(data)): raise RuntimeError('GLB 컨테이너 오류: '+key)
        points=[p for face in mesh.faces for p in face[:3]]
        lo=[min(p[k] for p in points) for k in range(3)]
        hi=[max(p[k] for p in points) for k in range(3)]
        footprint=[lo[0],lo[2],hi[0],hi[2]]
        metadata={'label_ko':label,'units':'meters','ground_y_m':0,'aabb_min_m':lo,'aabb_max_m':hi,
                  'bbox':None,'elevation_min':lo[1],'elevation_max':hi[1],
                  'resolution':{'type':'triangle_mesh','triangles':len(mesh.faces)},
                  'footprint_xz_m':footprint,'placement_padding_m':config['placement_padding_m'],
                  'scale_range':config['random_scale_range'],'georeferenced':False,'surveyed':False}
        scene=OUTPUT/f'{key}.tscn'
        text=f'''[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/generated/industrial/{key}.glb" id="1"]

[node name="{key}" type="Node3D"]
metadata/asset_type = "{key}"
metadata/units = "meters"
metadata/procedural = true
metadata/ground_y_m = 0.0

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="GroundOrigin" type="Marker3D" parent="."]
'''
        for index,p in enumerate(pipes.CONNECTORS.get(key,[])):
            text+=f'\n[node name="PipeConnector{index}" type="Marker3D" parent="."]\nposition = Vector3({p[0]}, {p[1]}, {p[2]})\n'
            direction=pipes.CONNECTOR_DIRECTIONS[key][index]
            angle=1.57079632679 if direction[0]<0 else -1.57079632679 if direction[0]>0 else 3.14159265359
            text+=f'rotation = Vector3(0, {angle}, 0)\n'
        scene.write_text(text,encoding='utf-8')
        for path in (model,scene):
            entries[path.name]={'file_path':'res://assets/generated/industrial/'+path.name,
                                'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                                'size_bytes':path.stat().st_size,'type':'industrial_asset','metadata':metadata}
        catalog[key]={'scene_path':'res://assets/generated/industrial/'+scene.name,
                      **metadata,'pipe_connectors_m':pipes.CONNECTORS.get(key,[]),
                      'pipe_connector_directions':pipes.CONNECTOR_DIRECTIONS.get(key,[])}
        models.append((key,label,mesh))
    atomic(OUTPUT/'catalog.json',{'version':1,'note_ko':config['note_ko'],'assets':catalog})
    render(models,OUTPUT/'preview.png')
    for name in ('catalog.json','preview.png'):
        path=OUTPUT/name
        entries[name]={'file_path':'res://assets/generated/industrial/'+name,
                       'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size_bytes':path.stat().st_size,
                       'bbox':None,'elevation_min':None,'elevation_max':None,
                       'resolution':{'width':2000,'height':90+430*((len(models)+4)//5)} if name.endswith('.png') else None}
    atomic(OUTPUT/'manifest.json',{'version':1,'assets':entries})
    merge(OUTPUT.parent/'manifest.json',{'industrial/'+k:v for k,v in entries.items()})
    modules=[]
    for path in sorted(Path(__file__).parent.glob('*.py')):
        source=path.read_text(encoding='utf-8')
        modules.append({'path':path.relative_to(ROOT).as_posix(),'lines':len(source.splitlines()),
                        'responsibility':source.splitlines()[0].strip('"')})
    for index in (ROOT/'module_index.json',ROOT/'godot_project/module_index.json'):
        before=index.read_bytes(); document=json.loads(before)
        section=next(k for k in document if k!='metadata' and isinstance(document[k],dict))
        document[section]['industrial_assets']={'description':'범용 절차적 공단 에셋','modules':modules}
        if index.read_bytes()!=before: raise RuntimeError('모듈 인덱스 동시 변경 감지')
        atomic(index,document)
    print(json.dumps({key:entry['resolution']['triangles'] for key,entry in catalog.items()}))
    apply_family('industrial')


if __name__=='__main__':
    main()
