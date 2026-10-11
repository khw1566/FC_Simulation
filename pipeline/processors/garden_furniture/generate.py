"""근경/원경 GLB와 독립 씬 및 경량성 매니페스트를 생성한다."""
import hashlib
import json
import sys
import struct
import importlib
from pathlib import Path

PACKAGE=Path(__file__).resolve().parent
sys.path.insert(0,str(PACKAGE.parent))
designs=importlib.import_module(PACKAGE.name+'.designs')
build,SPECS=designs.build,designs.SPECS
render=importlib.import_module(PACKAGE.name+'.preview').render


def main():
    default=PACKAGE.parents[2]/'godot_project/assets/generated/garden_furniture' if PACKAGE.name=='garden_furniture' else PACKAGE.parent/'assets'
    output=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else default
    output.mkdir(parents=True,exist_ok=True)
    assets={}
    previews=[]
    for kind,(label,switch,end) in SPECS.items():
        counts=[]
        for tier,far in [('near',False),('far',True)]:
            folder=output/tier
            folder.mkdir(exist_ok=True)
            mesh=build(kind,far)
            path=folder/(kind+'.glb')
            mesh.export(path,kind+'_'+tier)
            points=[p for f in mesh.faces for p in f[:3]]
            lo=[min(p[k] for p in points) for k in range(3)]
            hi=[max(p[k] for p in points) for k in range(3)]
            materials={f[4] for f in mesh.faces}
            entry={'name_ko':label,'lod':tier,'file_path':f'res://assets/generated/garden_furniture/{tier}/{kind}.glb',
                   'triangles':len(mesh.faces),'material_batches':len(materials),'size_bytes':path.stat().st_size,
                   'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                   'aabb_min_m':lo,'aabb_max_m':hi,'bbox':None,'georeferenced':False,
                   'min_elevation':lo[1],'max_elevation':hi[1],'resolution':{'type':'triangle_mesh','triangles':len(mesh.faces)}}
            assets[kind+'_'+tier]=entry
            scene=folder/(kind+'.tscn')
            scene.write_text(f'''[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="{entry['file_path']}" id="1"]
[node name="{kind}_{tier}" type="Node3D"]
metadata/name_ko = "{label} · {'원경' if far else '근경'}"
metadata/units = "meters"
metadata/triangles = {len(mesh.faces)}
[node name="Visual" parent="." instance=ExtResource("1")]
''',encoding='utf-8')
            entry['scene_path']=f'res://assets/generated/garden_furniture/{tier}/{kind}.tscn'
            entry['scene_sha256']=hashlib.sha256(scene.read_bytes()).hexdigest()
            data=path.read_bytes()
            magic,version,length=struct.unpack_from('<III',data)
            assert magic==0x46546C67 and version==2 and length==len(data)
            json_size=struct.unpack_from('<I',data,12)[0]
            doc=json.loads(data[20:20+json_size])
            for view in doc['bufferViews']:
                assert view['byteOffset']+view['byteLength']<=doc['buffers'][0]['byteLength']
            counts.append(len(mesh.faces))
            previews.append((label,tier,mesh))
        assert counts[1]<counts[0]
        assets[kind+'_near']['suggested_switch_m']=switch
        assets[kind+'_far']['suggested_cull_m']=end
    manifest={'version':1,'name_ko':'태화강 국가정원 시설물 6종 · 근경/원경 별도 모델',
              'units':'meters','up_axis':'Y','origin':'바닥 중심','assets':assets,
              'notes':'현장 실측 복제가 아닌 범용 배치용 디자인. 외부 텍스처와 충돌체 없음.'}
    (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    render(previews,output/'preview.png')
    print(json.dumps({key:value['triangles'] for key,value in assets.items()}))


if __name__=='__main__': main()
