"""게임과 분리된 전체 지도 수동 갱신 진입점."""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from simple_maps.sources import ROOT, read, resolve, digest
from simple_maps import raster, vectors, svg
from simple_maps.publish import atomic, publish, register_modules


def build(meta_path,config,force=False):
    original=meta_path.read_bytes()
    meta=json.loads(original)
    paths={resolve(meta['assets'][key]) for key in ('heightmap','watermask','sea_mask','river_mask','lake_mask','buildings_roads') if meta['assets'].get(key)}
    if meta.get('vector_source_meta'): paths.add(resolve(meta['vector_source_meta']))
    paths.update(ROOT/p for p in ('data/raw/ulsan_metro_80km/railway/osm_railways.json',
                                'data/raw/infrastructure/kanmon_straits_infra.json',
                                'data/raw/waterways/kanmon_straits_water.json',
                                'data/raw/ulsan_uc_west/waterways/ulsan_water.json'))
    paths.update((meta_path.parent/'hydro').glob('*.geojson'))
    paths.update((ROOT/'data/raw'/meta['id']/'waterways').glob('*.json'))
    if meta['id']=='southeast_mega_140km':
        additional=read(ROOT/'godot_project/assets/maps/ulsan_metro_80km/map_meta.json')
        paths.add(resolve(additional['assets']['buildings_roads']))
    paths.update(resolve(config[k+'_geojson'].format(map_id=meta['id'])) for k in ('harbors','shipping_routes'))
    fingerprints={str(p.relative_to(ROOT)):digest(p) if p.exists() else None for p in sorted(paths)}
    state={str(p):(p.stat().st_size,p.stat().st_mtime_ns) for p in paths if p.exists()}
    settings={k:v for k,v in config.items() if k not in ('background','colors','note_ko')}
    settings['processor_hashes']={p.name:digest(p) for p in Path(__file__).parent.glob('*.py') if p.name not in ('generate.py','publish.py','check.py')}
    key=hashlib.sha256(json.dumps([fingerprints,settings,meta['bbox'],meta['world_size_meters'],meta['min_elevation'],meta['max_elevation'],meta.get('sea_level',0)],sort_keys=True).encode()).hexdigest()
    cache=ROOT/'data/processed/simple_maps'/meta['id']
    cache.mkdir(parents=True,exist_ok=True)
    cache_path=cache/'layers.json'
    saved=read(cache_path) if cache_path.exists() else {}
    revision=hashlib.sha256((key+json.dumps(config,sort_keys=True)).encode()).hexdigest()[:16]
    output=meta_path.parent/'simple_map/revisions'/revision
    if not force and output.exists() and (output/'manifest.json').exists() and meta['assets'].get('tactical_map','').endswith('/'+revision+'/map.svg'):
        print(meta['id']+': 변경 없음',flush=True)
        return
    if not force and saved.get('fingerprint')==key:
        layers=saved['layers']
        print(meta['id']+': 마스크 캐시 재사용',flush=True)
    else:
        layers=raster.layers(meta,config)
        layers.update(vectors.layers(meta,config))
        atomic(cache_path,{'fingerprint':key,'sources':fingerprints,'layers':layers})
    index=svg.write(layers,config,output)
    for path,value in state.items():
        current=Path(path).stat()
        if (current.st_size,current.st_mtime_ns)!=value: raise RuntimeError(f'원본 동시 변경 감지: {path}')
    publish(meta_path,original,output,index)
    print(meta['id']+': SVG·마스크·타일 갱신 완료',flush=True)


def main():
    parser=argparse.ArgumentParser(description='전체 지도 수동 벡터 갱신')
    parser.add_argument('--maps',nargs='*',help='생략 시 등록된 지도 전체')
    parser.add_argument('--force',action='store_true')
    args=parser.parse_args()
    config=read(ROOT/'config/simple_vector_maps.json')
    available={p.parent.name for p in (ROOT/'godot_project/assets/maps').glob('*/map_meta.json')}
    if args.maps and set(args.maps)-available:
        parser.error('등록되지 않은 지도: '+', '.join(sorted(set(args.maps)-available)))
    lock=ROOT/'data/processed/simple_maps.lock'
    lock.parent.mkdir(parents=True,exist_ok=True)
    try: handle=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
    except FileExistsError: raise RuntimeError('수동 지도 갱신이 이미 실행 중입니다.')
    try:
        for path in sorted((ROOT/'godot_project/assets/maps').glob('*/map_meta.json')):
            if args.maps and path.parent.name not in args.maps: continue
            build(path,config,args.force)
        register_modules()
    finally:
        os.close(handle)
        lock.unlink()


if __name__=='__main__':
    main()
