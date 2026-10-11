"""수동 생성 결과의 해시 색인과 지도 참조 갱신."""

import json
import os
import xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image
from .sources import ROOT, read, digest

LEGEND = '청록: 해안선 · 주황: 대로 · 보라: 철로 · 하늘색: 강 · 파랑: 호수 · 갈색: 산지 · 회색: 소형맵 건물 · 빨강: 항구 · 초록: 항로'


def atomic(path,data):
    temporary=path.with_name(path.name+f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    os.replace(temporary,path)


def merge(path,updates):
    lock=path.with_name(path.name+'.simple_maps.lock')
    try: fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    except FileExistsError: raise RuntimeError(f'지도 인덱스 갱신 중입니다: {lock}')
    try:
        before=path.read_bytes() if path.exists() else b'{}'
        document=json.loads(before)
        document.setdefault('assets',{}).update(updates)
        if path.exists() and path.read_bytes()!=before:
            raise RuntimeError(f'다른 작업의 인덱스 변경을 감지했습니다: {path}')
        atomic(path,document)
    finally:
        os.close(fd)
        lock.unlink()


def publish(meta_path, original, folder, index):
    if meta_path.read_bytes()!=original: raise RuntimeError(f'지도 설정이 변경되었습니다: {meta_path}')
    meta=read(meta_path)
    uri='res://'+folder.relative_to(ROOT/'godot_project').as_posix()+'/'
    entries={}
    for path in sorted(folder.rglob('*')):
        if not path.is_file() or path.name=='manifest.json': continue
        relative=path.relative_to(folder).as_posix()
        if path.suffix=='.png':
            with Image.open(path) as image: resolution={'width':image.width,'height':image.height}
        elif path.suffix=='.svg':
            root=ET.parse(path).getroot()
            resolution={'type':'vector','viewbox':[float(v) for v in root.attrib['viewBox'].split()],
                        'display_width':int(root.attrib['width']),'display_height':int(root.attrib['height'])}
        else:
            resolution={'type':'vector_tile_index','grid':index['grid']}
        entries[f"simple_maps/{meta['id']}/{folder.name}/{relative}"]={
            'file_path':uri+relative,'sha256':digest(path),'size_bytes':path.stat().st_size,
            'bbox':meta['bbox'],'elevation_min':meta['min_elevation'],'elevation_max':meta['max_elevation'],
            'resolution':resolution,'type':'map_mask' if relative.startswith('masks/') else 'vector_map_asset'}
    atomic(folder/'manifest.json',{'version':1,'assets':entries})
    meta.setdefault('legacy_tactical_map',meta['assets'].get('tactical_map',''))
    meta['assets']['tactical_map']=uri+'map.svg'
    meta['preview_image']=uri+'map.svg'
    meta['simple_vector_map']={'tiles_index':uri+'tiles.json','manual_refresh':True,
                              'legend':LEGEND,'counts':index['counts'],
                              'navigation_status':'입력 GeoJSON이 없는 항구·항로는 빈 마스크',
                              'source_policy':'최신 로컬 원본을 수동으로 합성'}
    meta.setdefault('tactical_atlas',{})['legend']=LEGEND+' | 좌클릭: 위치 이동 · 우클릭 드래그: 이동 · 휠: 확대'
    meta['tactical_atlas']['road_count']=index['counts'].get('roads',0)
    if meta['id']=='ulsan_metro_80km' and meta.get('coverage',{}).get('roads',{}).get('coverage_complete'):
        meta['tactical_atlas']['detail_note']='80km 전체 OSM 도로 수집분. 생활도로·보행로는 얇은 선으로 표시한다.'
    if meta_path.read_bytes()!=original: raise RuntimeError('지도 설정 동시 변경 감지')
    atomic(meta_path,meta)
    # 기존 메타 자산의 해시도 함께 갱신한다.
    for manifest_path in (meta_path.parent/'manifest.json',ROOT/'godot_project/assets/generated/manifest.json'):
        updates=dict(entries)
        if manifest_path.exists():
            for key,entry in read(manifest_path).get('assets',{}).items():
                if entry.get('file_path')=='res://'+meta_path.relative_to(ROOT/'godot_project').as_posix():
                    updates[key]={**entry,'sha256':digest(meta_path),'size_bytes':meta_path.stat().st_size}
        merge(manifest_path,updates)


def register_modules():
    modules=[]
    for path in sorted((ROOT/'pipeline/processors/simple_maps').glob('*.py')):
        text=path.read_text(encoding='utf-8')
        modules.append({'path':path.relative_to(ROOT).as_posix(),'lines':len(text.splitlines()),
                        'responsibility':text.splitlines()[0].strip('"')})
    for relative,description in (
        ('pipeline/update_map_images.ps1','게임과 분리된 수동 지도 갱신 명령'),
        ('godot_project/scripts/views/vector_map_tiles.gd','현재 화면의 SVG 타일 표시 및 확대 선폭·캐시 제어'),
        ('godot_project/scripts/services/vector_map_display.gd','수동 생성 벡터 지도의 HUD 연결')):
        path=ROOT/relative
        modules.append({'path':relative,'lines':len(path.read_text(encoding='utf-8').splitlines()),
                        'responsibility':description})
    for index in (ROOT/'module_index.json',ROOT/'godot_project/module_index.json'):
        original=index.read_bytes()
        document=json.loads(original)
        section=next(k for k in document if k!='metadata' and isinstance(document[k],dict))
        document[section]['simple_vector_maps']={'description':'계층 마스크 합성과 수동 SVG 지도 갱신','modules':modules}
        for category in document[section].values():
            if not isinstance(category,dict): continue
            for module in category.get('modules',[]):
                if module.get('path')=='godot_project/scripts/views/map_hud_view.gd':
                    module['lines']=len((ROOT/module['path']).read_text(encoding='utf-8').splitlines())
        if index.read_bytes()!=original: raise RuntimeError(f'모듈 인덱스 동시 변경 감지: {index}')
        atomic(index,document)
