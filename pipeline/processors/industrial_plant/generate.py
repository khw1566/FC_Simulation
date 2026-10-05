"""플랜트 에셋만 생성하고 조립 예제·전용 매니페스트를 등록."""

import hashlib
import json
import math
import os
import struct
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from industrial_plant import towers,routing,effects
from industrial.preview import render
from simple_maps.publish import atomic,merge
from industrial_lighting.apply import apply_family

OUT=ROOT/'godot_project/assets/generated/industrial_plant'
URI='res://assets/generated/industrial_plant/'


def write(path,text):
    temporary=path.with_name(path.name+f'.{os.getpid()}.tmp')
    temporary.write_text(text,encoding='utf-8'); os.replace(temporary,path)


def marker(index,position,direction):
    # Marker3D -Z 바깥 방향. 같은 배관 포트는 180도 반대로 결합.
    angle=math.atan2(-direction[0],-direction[2])
    return f'''\n[node name="PipeConnector{index}" type="Marker3D" parent="."]
position = Vector3({', '.join(map(str,position))})
rotation = Vector3(0, {angle}, 0)
metadata/profile = "triple_pipe_032_spacing_110"
metadata/lane_count = 3
metadata/diameter_m = 0.64
metadata/lane_spacing_m = 1.1
'''


def model_scene(key,ports,outlets,preset):
    extra=f'[ext_resource type="PackedScene" path="{URI}{preset}.tscn" id="2"]\n' if preset else ''
    text=f'''[gd_scene load_steps={3 if preset else 2} format=3]

[ext_resource type="PackedScene" path="{URI}{key}.glb" id="1"]
{extra}
[node name="{key}" type="Node3D"]
metadata/asset_type = "{key}"
metadata/units = "meters"
metadata/procedural = true

[node name="Visual" parent="." instance=ExtResource("1")]

[node name="GroundOrigin" type="Marker3D" parent="."]
'''
    for i,(position,direction) in enumerate(ports): text+=marker(i,position,direction)
    for i,position in enumerate(outlets):
        text+=f'\n[node name="SmokeOutlet{i}" type="Marker3D" parent="."]\nposition = Vector3({", ".join(map(str,position))})\n'
        if preset: text+=f'\n[node name="Plume" parent="SmokeOutlet{i}" instance=ExtResource("2")]\n'
    return text


def demo():
    placements=[('rack_straight',(0,0,0),0),('rack_tee',(24,0,0),0),
                ('rack_elbow',(48,0,0),0),('rack_straight',(24,0,24),-math.pi/2),
                ('stack_concrete',(24,0,48),-math.pi/2),('scrubber_tower',(48,0,24),-math.pi/2),
                ('rack_riser',(-24,0,0),math.pi),('rack_double',(-48,0,0),0),
                ('stack_triple',(-24,0,-28),0),('process_column',(-48,0,-28),0),
                ('flare_lattice',(0,0,-36),0)]
    unique=list(dict.fromkeys(key for key,_,_ in placements))
    text=f'[gd_scene load_steps={len(unique)+1} format=3]\n\n'
    for i,key in enumerate(unique): text+=f'[ext_resource type="PackedScene" path="{URI}{key}.tscn" id="{i+1}"]\n'
    text+='\n[node name="PlantAssemblyDemo" type="Node3D"]\n'
    for i,(key,p,angle) in enumerate(placements):
        text+=f'\n[node name="{key}_{i}" parent="." instance=ExtResource("{unique.index(key)+1}" )]\nposition = Vector3({", ".join(map(str,p))})\nrotation = Vector3(0, {angle}, 0)\n'
    return text,placements


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    models=[]; catalog={}; entries={}
    for key,preset in effects.PRESETS.items(): write(OUT/f'{key}.tscn',effects.scene(key))
    for key in list(towers.SPECS)+list(routing.PORTS):
        is_tower=key in towers.SPECS
        label,outlets,preset=towers.SPECS[key] if is_tower else (routing.LABELS[key],[],None)
        ports=[([-12,5,0],[-1,0,0])] if is_tower else routing.PORTS[key]
        mesh=(towers if is_tower else routing).build(key)
        path=OUT/f'{key}.glb'; temporary=path.with_name(path.name+'.tmp')
        mesh.export(temporary,key); data=temporary.read_bytes()
        assert struct.unpack_from('<III',data)==(0x46546C67,2,len(data))
        assert all(math.isfinite(v) for face in mesh.faces for point in face[:4] for v in point)
        os.replace(temporary,path)
        vertices=[p for f in mesh.faces for p in f[:3]]
        lo=[min(p[i] for p in vertices) for i in range(3)]; hi=[max(p[i] for p in vertices) for i in range(3)]
        metadata={'label_ko':label,'bbox':None,'aabb_min_m':lo,'aabb_max_m':hi,'units':'meters',
                  'elevation_min':lo[1],'elevation_max':hi[1],'resolution':{'type':'triangle_mesh','triangles':len(mesh.faces)},
                  'ground_y_m':0,'surveyed':False,'georeferenced':False,'pipe_profile':'triple_pipe_032_spacing_110',
                  'pipe_connectors_m':[p for p,d in ports],'pipe_connector_directions':[d for p,d in ports],
                  'smoke_outlets_m':outlets,'default_plume':preset,'scene_path':URI+key+'.tscn'}
        catalog[key]=metadata; models.append((key,label,mesh))
        write(OUT/f'{key}.tscn',model_scene(key,ports,outlets,preset))
    text,placements=demo(); write(OUT/'plant_assembly_demo.tscn',text)
    atomic(OUT/'catalog.json',{'version':1,'note_ko':'울산 공단의 스카이라인을 위한 범용 실루엣. 실제 시설 배치·사양 재현 아님.',
                             'connector_axis':'-Z outward','assets':catalog,'plume_presets':list(effects.PRESETS),
                             'assembly_demo':placements})
    render(models,OUT/'preview.png')
    for path in sorted(OUT.iterdir()):
        if path.suffix not in ('.glb','.tscn','.json','.png','.md') or path.name=='manifest.json': continue
        meta=catalog.get(path.stem,{})
        entries[path.name]={'file_path':URI+path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                           'size_bytes':path.stat().st_size,'type':'industrial_plant_asset','metadata':meta,
                           'bbox':None,'elevation_min':meta.get('elevation_min'),'elevation_max':meta.get('elevation_max'),
                           'resolution':({'width':2000,'height':1380} if path.suffix=='.png' else meta.get('resolution'))}
    atomic(OUT/'manifest.json',{'version':1,'assets':entries})
    merge(OUT.parent/'manifest.json',{'industrial_plant/'+k:v for k,v in entries.items()})
    modules=[]
    for path in list(Path(__file__).parent.glob('*.py'))+list((ROOT/'godot_project/scripts/industrial_plant').glob('*.gd')):
        source=path.read_text(encoding='utf-8')
        modules.append({'path':path.relative_to(ROOT).as_posix(),'lines':len(source.splitlines())})
    for path in (ROOT/'module_index.json',ROOT/'godot_project/module_index.json'):
        before=path.read_bytes(); doc=json.loads(before)
        section=next(k for k in doc if k!='metadata' and isinstance(doc[k],dict))
        doc[section]['industrial_plant']={'description':'조립 가능한 플랜트 탑·배관·연기','modules':modules}
        if path.read_bytes()!=before: raise RuntimeError('모듈 인덱스 동시 변경: 재실행 필요')
        atomic(path,doc)
    print(json.dumps({key:meta['resolution']['triangles'] for key,meta in catalog.items()}))
    apply_family('industrial_plant')


if __name__=='__main__': main()
