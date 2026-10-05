"""GLB 원본을 보존하고 야간 리그·씬 참조·색인만 갱신."""

import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from industrial_lighting.layouts import layout
from industrial_lighting.scenes import scene
from simple_maps.publish import atomic,merge

OUT=ROOT/'godot_project/assets/generated/industrial_lighting'
URI='res://assets/generated/industrial_lighting/'


def write(path,data,original=None):
    if original is not None and path.read_bytes()!=original:
        raise RuntimeError('다른 작업의 변경 감지: '+str(path))
    temporary=path.with_name(path.name+f'.{os.getpid()}.tmp')
    temporary.write_bytes(data)
    if original is not None and path.read_bytes()!=original:
        temporary.unlink()
        raise RuntimeError('교체 직전 다른 작업의 변경 감지: '+str(path))
    os.replace(temporary,path)


def attach(text,filename):
    # 같은 소유 블록만 교체하며 다른 에이전트가 추가한 노드는 유지한다.
    already='id="NightRig"' in text
    text=re.sub(r'; NIGHT_RIG_RESOURCE_BEGIN\n.*?; NIGHT_RIG_RESOURCE_END\n','',text,flags=re.S)
    text=re.sub(r'; NIGHT_RIG_NODE_BEGIN\n.*?; NIGHT_RIG_NODE_END\n','',text,flags=re.S)
    if not already:
        text=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m[1])+1),text,count=1)
    resource=f'; NIGHT_RIG_RESOURCE_BEGIN\n[ext_resource type="PackedScene" path="{URI}{filename}" id="NightRig"]\n; NIGHT_RIG_RESOURCE_END\n\n'
    start=text.index('[node ')
    return text[:start]+resource+text[start:]+'''\n; NIGHT_RIG_NODE_BEGIN
[node name="NightLighting" parent="." instance=ExtResource("NightRig")]
; NIGHT_RIG_NODE_END
'''


def entry(path,meta=None):
    return {'file_path':'res://'+path.relative_to(ROOT/'godot_project').as_posix(),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size_bytes':path.stat().st_size,
            'bbox':None,'elevation_min':None,'elevation_max':None,'resolution':None,
            'type':'industrial_night_lighting','metadata':meta or {}}


def apply_family(family):
    folder=OUT.parent/family
    catalog_path=folder/'catalog.json'; manifest_path=folder/'manifest.json'
    if not catalog_path.exists(): return
    OUT.mkdir(parents=True,exist_ok=True)
    lock=OUT/'apply.lock'; fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    try:
        before_catalog=catalog_path.read_bytes(); before_manifest=manifest_path.read_bytes()
        catalog=json.loads(before_catalog); manifest=json.loads(before_manifest)
        own_catalog_path=OUT/'catalog.json'; own_manifest_path=OUT/'manifest.json'
        own_catalog=json.loads(own_catalog_path.read_bytes()) if own_catalog_path.exists() else {'version':1,'assets':{}}
        own_manifest=json.loads(own_manifest_path.read_bytes()) if own_manifest_path.exists() else {'version':1,'assets':{}}
        updates={}; summary={}
        for key,meta in catalog['assets'].items():
            fixtures,lights=layout(key,meta)
            filename=f'{family}--{key}.tscn'; rig=OUT/filename
            write(rig,scene(fixtures,lights).encode('utf-8'))
            info={'scene_path':URI+filename,'fixture_count':len(fixtures),'local_light_count':len(lights),
                  'shadow_enabled':False,'distance_fade_m':[350,550],
                  'automatic_time':True,'fallback_night_factor':1.0,'source_asset':family+'/'+key}
            source=folder/f'{key}.tscn'; original=source.read_bytes()
            write(source,attach(original.decode('utf-8'),filename).encode('utf-8'),original)
            meta['night_lighting']=info
            existing=manifest['assets'][source.name]
            existing.update({'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'size_bytes':source.stat().st_size})
            existing.setdefault('metadata',{})['night_lighting']=info
            updates[family+'/'+source.name]=existing
            own_catalog['assets'][family+'/'+key]=info
            own_manifest['assets'][filename]=entry(rig,info)
            updates['industrial_lighting/'+filename]=own_manifest['assets'][filename]
            summary[key]={'fixtures':len(fixtures),'lights':len(lights)}
        write(catalog_path,(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),before_catalog)
        updates[family+'/catalog.json']=entry(catalog_path)
        # 카탈로그 해시도 계열 매니페스트에 최신화한다.
        manifest['assets']['catalog.json'].update({'sha256':updates[family+'/catalog.json']['sha256'],
                                                   'size_bytes':catalog_path.stat().st_size})
        if (folder/'README.md').exists():
            document=manifest['assets'].get('README.md',entry(folder/'README.md'))
            document.update({'sha256':hashlib.sha256((folder/'README.md').read_bytes()).hexdigest(),
                             'size_bytes':(folder/'README.md').stat().st_size,'type':'asset_document'})
            manifest['assets']['README.md']=document
            updates[family+'/README.md']=document
        write(manifest_path,(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),before_manifest)
        atomic(own_catalog_path,own_catalog)
        own_manifest['assets']['catalog.json']=entry(own_catalog_path)
        for name in ('README.md',):
            if (OUT/name).exists(): own_manifest['assets'][name]=entry(OUT/name)
        atomic(own_manifest_path,own_manifest)
        updates.update({'industrial_lighting/'+k:v for k,v in own_manifest['assets'].items()})
        updates[family+'/catalog.json']=manifest['assets']['catalog.json']
        for attempt in range(5):
            try:
                merge(OUT.parent/'manifest.json',updates)
                break
            except PermissionError:
                if attempt==4: raise
                time.sleep(.1*(attempt+1))
        register_modules()
        print(json.dumps({'family':family,'assets':len(summary),'layouts':summary}))
    finally:
        os.close(fd); lock.unlink()


def register_modules():
    modules=[]
    paths=list(Path(__file__).parent.glob('*.py'))+list(Path(__file__).parent.glob('*.gd'))
    paths+=list((ROOT/'godot_project/scripts/industrial_lighting').glob('*.gd'))
    for path in sorted(paths):
        modules.append({'path':path.relative_to(ROOT).as_posix(),'lines':len(path.read_text(encoding='utf-8').splitlines())})
    for path in (ROOT/'module_index.json',ROOT/'godot_project/module_index.json'):
        original=path.read_bytes(); doc=json.loads(original)
        section=next(k for k in doc if k!='metadata' and isinstance(doc[k],dict))
        doc[section]['industrial_lighting']={'description':'시설별 야간 광원·발광·주야간 연동','modules':modules}
        write(path,(json.dumps(doc,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),original)


if __name__=='__main__':
    for family in ('industrial','industrial_plant'): apply_family(family)
