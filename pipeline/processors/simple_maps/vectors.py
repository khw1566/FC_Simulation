"""도로·철도·건물·수계 및 작업 중 항만 계층의 벡터 어댑터."""

from shapely.geometry import shape, mapping, box
from shapely.ops import transform
from .sources import ROOT, resolve, read, array, geo, local, osm_lines, osm_hydro


def geographic(features, meta, size):
    bounds = box(0,0,size,size)
    result = []
    def project(x,y,z=None):
        b=meta['bbox']
        return ((x-b['west'])/(b['east']-b['west'])*size,
                (b['north']-y)/(b['north']-b['south'])*size)
    for feature in features:
        geometry = feature.get('geometry')
        if not geometry: continue
        value = transform(project,shape(geometry)).intersection(bounds)
        if not value.is_empty:
            result.append({'geometry':mapping(value),'width':2})
    return result


def layers(meta,config):
    n = config['canvas_size']
    result = {k:[] for k in ('roads','railways','buildings','harbors','shipping_routes')}
    assets = meta['assets']
    source = read(resolve(meta['vector_source_meta'])) if meta.get('vector_source_meta') else meta
    path = resolve(assets['buildings_roads'])
    road_sources=[(path,source)]
    if meta['id']=='southeast_mega_140km':
        additional=read(ROOT/'godot_project/assets/maps/ulsan_metro_80km/map_meta.json')
        road_sources.append((resolve(additional['assets']['buildings_roads']),additional))
    for road_path,road_meta in road_sources:
        for road in array(road_path,'roads'):
            types=config.get('road_types_by_map',{}).get(meta['id'],config['road_types'])
            major=road.get('type','').removesuffix('_link') in types
            wide=road.get('width',0)>=config['unclassified_major_min_width_m']
            if not major and not wide: continue
            points=[local(p,road_meta,meta,n) for p in road.get('points',[])]
            if len(points)>1:
                detail=meta['id']=='ulsan_metro_80km' and road.get('type','').removesuffix('_link') not in ('motorway','trunk','primary','secondary','tertiary')
                result['roads'].append({'geometry':{'type':'LineString','coordinates':points},
                                        'width':max(.3 if detail else 1.4,road.get('width',12)/meta['world_size_meters']*n),
                                        'opacity':.6 if detail else 1})
    if meta['world_size_meters'] <= config['building_max_world_size_m']:
        for building in array(path,'buildings'):
            polygon = building.get('polygon',[])
            if not polygon and 'center' in building and 'size' in building:
                x,_,z=building['center']; w,_,d=building['size']
                polygon=[[x-w/2,z-d/2],[x+w/2,z-d/2],[x+w/2,z+d/2],[x-w/2,z+d/2]]
            if len(polygon)<3: continue
            points=[local(p,source,meta,n) for p in polygon]
            if points[-1]!=points[0]: points.append(points[0])
            result['buildings'].append({'geometry':{'type':'Polygon','coordinates':[points]}})
    raw = ROOT/'data/raw/ulsan_metro_80km/railway/osm_railways.json'
    lines = osm_lines(raw,lambda tags:tags.get('railway')=='rail')
    infra = ROOT/'data/raw/infrastructure/kanmon_straits_infra.json'
    if meta['bbox']['west']>130:
        lines = osm_lines(infra,lambda tags:tags.get('railway') in ('rail','light_rail'))
        coast = osm_lines(infra,lambda tags:tags.get('natural')=='coastline')
        result['coastline'] = geographic([{'geometry':{'type':'LineString','coordinates':p}} for p in coast],meta,n)
    result['railways'] = geographic([{'geometry':{'type':'LineString','coordinates':p}} for p in lines],meta,n)
    for key in ('harbors','shipping_routes'):
        target=resolve(config[key+'_geojson'].format(map_id=meta['id']))
        if target.exists():
            result[key]=geographic(read(target).get('features',[]),meta,n)
    # 가능하면 원본 수계 형상으로 하천/호수를 구분한다.
    folder = ROOT/'godot_project/assets/maps'/meta['id']/'hydro'
    if (folder/'river.geojson').exists():
        for key,name in (('rivers','river'),('lakes','lake'),('coastline','coastline')):
            result[key]=geographic(read(folder/f'{name}.geojson')['features'],meta,n)
    else:
        rawwater = ROOT/('data/raw/waterways/kanmon_straits_water.json' if meta['bbox']['west']>130
                        else f"data/raw/{meta['id']}/waterways/{'ulsan' if meta['id']=='ulsan_uc_west' else meta['id']}_water.json")
        if rawwater.exists():
            groups=osm_hydro(rawwater)
            for key,name in (('rivers','river'),('lakes','lake')):
                extracted=geographic(groups[name],meta,n)
                if extracted: result[key]=extracted
    bounds=box(0,0,n,n)
    for key,features in result.items():
        clipped=[]
        for feature in features:
            value=shape(feature['geometry'])
            if not value.is_valid: value=value.buffer(0)
            value=value.intersection(bounds)
            if value.is_empty: continue
            feature['geometry']=mapping(value.simplify(.4,preserve_topology=True))
            if value.geom_type=='Point': feature['radius']=6
            clipped.append(feature)
        result[key]=clipped
    return result
