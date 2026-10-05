"""계층 합성 SVG, 흑백 마스크와 확대용 SVG 타일 출력."""

import json
from html import escape
from PIL import Image, ImageDraw, ImageColor
from shapely.geometry import shape, mapping, box
from shapely.strtree import STRtree

ORDER = ('sea','mountains','rivers','lakes','buildings','roads','railways','coastline','shipping_routes','harbors')


def commands(points, close=False):
    if not points: return ''
    return 'M'+' L'.join(f'{p[0]:.2f},{p[1]:.2f}' for p in points)+(' Z' if close else '')


def element(geometry,color,width=2,opacity=1,radius=6):
    kind,coords=geometry['type'],geometry.get('coordinates',[])
    if kind=='GeometryCollection':
        return ''.join(element(g,color,width,opacity,radius) for g in geometry['geometries'])
    if kind.startswith('Multi'):
        return ''.join(element({'type':kind[5:],'coordinates':c},color,width,opacity,radius) for c in coords)
    if kind=='Point':
        return f'<circle cx="{coords[0]:.2f}" cy="{coords[1]:.2f}" r="{radius}" fill="{color}"/>'
    if kind=='Polygon':
        data=' '.join(commands(r,True) for r in coords)
        return f'<path d="{data}" fill="{color}" fill-rule="evenodd" opacity="{opacity}"/>'
    if kind=='LineString':
        return f'<path d="{commands(coords)}" fill="none" stroke="{color}" stroke-width="{width:.2f}" stroke-linecap="round" stroke-linejoin="round" opacity="{opacity}"/>'
    return ''


def document(layers,config,view=None,mask=None):
    n=config['canvas_size']
    x,y,w,h=view or (0,0,n,n)
    width=config['canvas_size']//config['tile_grid'] if view else 2048
    output=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{width}" viewBox="{x} {y} {w} {h}">']
    background='#000000' if mask else config['background']
    output.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{background}"/>')
    for key in ORDER:
        if mask and key!=mask: continue
        color='#ffffff' if mask else config['colors'][key]
        output.append(f'<g id="{escape(key)}">')
        output.extend(element(f['geometry'],color,f.get('width',2),f.get('opacity',1),f.get('radius',6)) for f in layers.get(key,[]))
        output.append('</g>')
    output.append('</svg>')
    return '\n'.join(output)


def raster_layer(features,size,canvas):
    image=Image.new('L',(size,size),0)
    draw=ImageDraw.Draw(image)
    scale=size/canvas
    def paint(g,fill,width=2,radius=6):
        kind,c=g['type'],g.get('coordinates',[])
        if kind=='GeometryCollection':
            for child in g['geometries']: paint(child,fill,width,radius)
        elif kind.startswith('Multi'):
            for child in c: paint({'type':kind[5:],'coordinates':child},fill,width,radius)
        elif kind=='Polygon':
            points=[(p[0]*scale,p[1]*scale) for ring in c for p in ring]
            x0,y0=max(0,int(min(p[0] for p in points))),max(0,int(min(p[1] for p in points)))
            x1,y1=min(size,int(max(p[0] for p in points))+2),min(size,int(max(p[1] for p in points))+2)
            if x1<=x0 or y1<=y0: return
            local=Image.new('L',(x1-x0,y1-y0),0); painter=ImageDraw.Draw(local)
            for i,ring in enumerate(c):
                painter.polygon([(p[0]*scale-x0,p[1]*scale-y0) for p in ring],fill=fill if i==0 else 0)
            from PIL import ImageChops
            image.paste(ImageChops.lighter(image.crop((x0,y0,x1,y1)),local),(x0,y0))
        elif kind=='LineString' and len(c)>1:
            draw.line([(p[0]*scale,p[1]*scale) for p in c],fill=fill,width=max(1,round(width*scale)),joint='curve')
        elif kind=='Point':
            x,y=c[0]*scale,c[1]*scale; r=max(2,radius*scale)
            draw.ellipse((x-r,y-r,x+r,y+r),fill=fill)
    for f in features:
        paint(f['geometry'],round(f.get('opacity',1)*255),f.get('width',2),f.get('radius',6))
    return image


def write(layers,config,folder):
    folder.mkdir(parents=True,exist_ok=True)
    (folder/'masks').mkdir(exist_ok=True)
    (folder/'tiles').mkdir(exist_ok=True)
    (folder/'map.svg').write_text(document(layers,config),encoding='utf-8')
    size=config['raster_mask_size']
    composite=Image.new('RGB',(size,size),config['background'])
    for key in ORDER:
        mask=raster_layer(layers.get(key,[]),size,config['canvas_size'])
        mask.save(folder/'masks'/f'{key}.png')
        (folder/'masks'/f'{key}.svg').write_text(document(layers,config,mask=key),encoding='utf-8')
        color=Image.new('RGB',(size,size),config['colors'][key])
        composite.paste(color,(0,0),mask)
    composite.save(folder/'preview.png')
    entries=[]
    for key in ORDER:
        for f in layers.get(key,[]):
            geometry=shape(f['geometry'])
            if not geometry.is_empty: entries.append((key,f,geometry))
    tree=STRtree([e[2] for e in entries])
    grid,n=config['tile_grid'],config['canvas_size']
    step=n/grid
    for row in range(grid):
        for col in range(grid):
            extent=box(col*step,row*step,(col+1)*step,(row+1)*step)
            tile={key:[] for key in ORDER}
            # 높이 계층의 합성 순서를 원본 순서대로 보존한다.
            for index in sorted(tree.query(extent).tolist()):
                key,f,g=entries[index]
                clipped=g.intersection(extent)
                if not clipped.is_empty:
                    tile[key].append({**f,'geometry':mapping(clipped)})
            (folder/'tiles'/f'{col}_{row}.svg').write_text(
                document(tile,config,(col*step,row*step,step,step)),encoding='utf-8')
    index={'version':1,'grid':grid,'canvas_size':n,'tile_svg_size':int(step),
           'map':'map.svg','pattern':'tiles/{x}_{y}.svg','colors':config['colors'],
           'counts':{key:len(layers.get(key,[])) for key in ORDER}}
    (folder/'tiles.json').write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
    return index
