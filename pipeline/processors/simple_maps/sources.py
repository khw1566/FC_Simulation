"""원본 좌표 투영과 안정된 로컬 자료 읽기."""

import hashlib
import json
import mmap
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def resolve(uri):
    return ROOT/'godot_project'/uri[6:] if uri.startswith('res://') else ROOT/uri


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):
            value.update(block)
    return value.hexdigest()


def array(path, key):
    # 광역 건물 수십만 개를 읽지 않고 필요한 최상위 배열만 디코딩한다.
    before = path.stat()
    with path.open('rb') as stream, mmap.mmap(stream.fileno(),0,access=mmap.ACCESS_READ) as data:
        match = re.search(rb'"'+key.encode()+rb'"\s*:\s*\[',data)
        if match is None:
            return []
        start, depth, quoted, escape = match.end()-1, 0, False, False
        end = start
        for end in range(start,len(data)):
            char = data[end]
            if quoted:
                if escape: escape = False
                elif char == 92: escape = True
                elif char == 34: quoted = False
            elif char == 34: quoted = True
            elif char == 91: depth += 1
            elif char == 93:
                depth -= 1
                if depth == 0: break
        result = json.loads(data[start:end+1])
    after = path.stat()
    if (before.st_size,before.st_mtime_ns) != (after.st_size,after.st_mtime_ns):
        raise RuntimeError(f'원본이 쓰기 중입니다: {path}')
    return result


def geo(point, bbox, size):
    return [(point[0]-bbox['west'])/(bbox['east']-bbox['west'])*size,
            (bbox['north']-point[1])/(bbox['north']-bbox['south'])*size]


def local(point, source, target, size):
    bbox, world = source['bbox'], source['world_size_meters']
    z = point[2] if len(point) > 2 else point[1]
    lon = bbox['west']+(point[0]/world+.5)*(bbox['east']-bbox['west'])
    lat = bbox['north']-(z/world+.5)*(bbox['north']-bbox['south'])
    return geo((lon,lat),target['bbox'],size)


def osm_lines(path, wanted):
    if not path.exists(): return []
    data = read(path)
    nodes = {e['id']:[e['lon'],e['lat']] for e in data.get('elements',[]) if e['type']=='node'}
    result = []
    for e in data.get('elements',[]):
        tags = e.get('tags',{})
        if e['type'] != 'way' or not wanted(tags): continue
        points = [[p['lon'],p['lat']] for p in e.get('geometry',[])]
        if not points: points = [nodes[n] for n in e.get('nodes',[]) if n in nodes]
        if len(points)>1: result.append(points)
    return result


def osm_hydro(path):
    from hydro_geometry import HydroGeometry
    data=read(path)
    nodes={e['id']:[e['lon'],e['lat']] for e in data.get('elements',[]) if e['type']=='node'}
    ways={e['id']:dict(e) for e in data.get('elements',[]) if e['type']=='way'}
    for way in ways.values():
        if not way.get('geometry'):
            way['geometry']=[{'lon':nodes[n][0],'lat':nodes[n][1]} for n in way.get('nodes',[]) if n in nodes]
    elements=list(ways.values())
    for entry in data.get('elements',[]):
        if entry['type']!='relation': continue
        relation=dict(entry)
        relation['members']=[{**m,'geometry':m.get('geometry',ways.get(m.get('ref'),{}).get('geometry',[]))}
                             for m in entry.get('members',[])]
        elements.append(relation)
    selected=[e for e in elements if e.get('tags',{}).get('natural') in ('water','coastline')
              or 'waterway' in e.get('tags',{}) or e.get('tags',{}).get('landuse')=='reservoir']
    return HydroGeometry().classify({'elements':selected})
