"""DEM과 수역 마스크를 단순 벡터 영역으로 변환한다."""

from collections import deque
import numpy as np
from PIL import Image
from shapely.geometry import LineString, mapping
from shapely.ops import polygonize, unary_union
from .sources import resolve


def image(uri, size, binary=False):
    with Image.open(resolve(uri)) as source:
        return np.asarray(source.convert('L' if binary else 'F').resize(
            (size,size),Image.Resampling.NEAREST if binary else Image.Resampling.BILINEAR))


def areas(mask, canvas, tolerance=1):
    mask = np.asarray(mask,dtype=bool)
    padded = np.pad(mask,1)
    edges = {}
    for dy,dx,offsets in ((-1,0,((0,0),(1,0))), (0,1,((1,0),(1,1))),
                         (1,0,((1,1),(0,1))), (0,-1,((0,1),(0,0)))):
        neighbor = padded[1+dy:1+dy+mask.shape[0],1+dx:1+dx+mask.shape[1]]
        yy,xx = np.where(mask & ~neighbor)
        for y,x in zip(yy.tolist(),xx.tolist()):
            a,b = offsets
            edges.setdefault((x+a[0],y+a[1]),[]).append((x+b[0],y+b[1]))
    rings = []
    while edges:
        start = next(iter(edges))
        ring, current = [start], start
        while current in edges:
            destinations = edges[current]
            following = destinations.pop()
            if not destinations: del edges[current]
            ring.append(following)
            current = following
            if current == start: break
        if len(ring)>3 and ring[-1]==start:
            rings.append(LineString(ring))
    scale = canvas/mask.shape[0]
    result = []
    # 대각선으로 맞닿은 픽셀 경계를 교차점에서 나눠 큰 수역의 소실을 막는다.
    for polygon in polygonize(unary_union(rings)):
        point = polygon.representative_point()
        x,y = min(mask.shape[1]-1,int(point.x)),min(mask.shape[0]-1,int(point.y))
        if not mask[y,x] or polygon.area < 1: continue
        simplified = polygon.simplify(tolerance/scale,preserve_topology=True)
        geometry = mapping(simplified)
        geometry['coordinates'] = [[[round(x*scale,2),round(y*scale,2)] for x,y in ring]
                                   for ring in geometry['coordinates']]
        result.append(geometry)
    return result


def border_sea(water):
    visited = np.zeros(water.shape,dtype=bool)
    n = water.shape[0]
    pending = deque()
    for i in range(n):
        for p in ((0,i),(n-1,i),(i,0),(i,n-1)):
            if water[p] and not visited[p]:
                visited[p]=True
                pending.append(p)
    while pending:
        y,x = pending.popleft()
        for yy,xx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
            if 0<=yy<n and 0<=xx<n and water[yy,xx] and not visited[yy,xx]:
                visited[yy,xx]=True
                pending.append((yy,xx))
    return visited


def layers(meta, config):
    size, canvas = config['water_sample_size'], config['canvas_size']
    assets = meta['assets']
    water = image(assets['watermask'],size,True)>100
    sea = image(assets['sea_mask'],size,True)>100 if assets.get('sea_mask') else (
        border_sea(water) if meta.get('sea_level',0)>-100 else np.zeros_like(water))
    result = {'sea':[{'geometry':g} for g in areas(sea,canvas)]}
    if assets.get('river_mask') or assets.get('lake_mask'):
        for name,key in (('rivers','river_mask'),('lakes','lake_mask')):
            result[name] = [{'geometry':g} for g in areas(image(assets[key],size,True)>80,canvas)] if assets.get(key) else []
    else:
        result['rivers'] = [{'geometry':g} for g in areas(water & ~sea,canvas)]
        result['lakes'] = []
    n = config['terrain_sample_size']
    height = image(assets['heightmap'],n)
    height = meta['min_elevation']+height/65535*(meta['max_elevation']-meta['min_elevation'])
    wet = np.asarray(Image.fromarray((water*255).astype('uint8')).resize((n,n),Image.Resampling.NEAREST))>0
    result['mountains'] = []
    for i,level in enumerate(config['mountain_levels_m']):
        result['mountains'].extend({'geometry':g,'opacity':.18+i*.08,'elevation_min':level}
                                   for g in areas((height>=level)&~wet,canvas,tolerance=3))
    # 해안선은 바다 외곽 경계이며 지도 사각 테두리는 제외한다.
    coast = []
    for entry in result['sea']:
        for ring in entry['geometry']['coordinates']:
            segment = []
            for p in ring:
                if p[0] in (0,canvas) or p[1] in (0,canvas):
                    if len(segment)>1: coast.append({'geometry':{'type':'LineString','coordinates':segment},'width':2})
                    segment=[]
                else: segment.append(p)
            if len(segment)>1: coast.append({'geometry':{'type':'LineString','coordinates':segment},'width':2})
    result['coastline'] = coast
    return result
