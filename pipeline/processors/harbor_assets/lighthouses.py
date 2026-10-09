"""색과 실루엣이 다른 등대 6종. 렌즈는 단색 발광으로만 표현한다."""
import math
from .asset import HarborAsset


def build_one(key,label,height,style,color,lens):
    a=HarborAsset(key,label,"lighthouse")
    a.mesh.box((0,.15,0),(3.2,.3,3.2),"concrete_dark")
    if style=="square":
        a.mesh.box((0,height*.42,0),(2.2,height*.84,2.2),"white")
        for y in (height*.25,height*.55): a.mesh.box((0,y,1.11),(.55,.9,.03),"glass")
    elif style=="lattice":
        for x in (-.8,.8):
            for z in (-.8,.8):
                a.mesh.beam((x,.3,z),(x*.45,height*.8,z*.45),.15,.15,color)
                a.mesh.beam((x,.3,z),(-x*.45,height*.8,z*.45),.09,.09,color)
    else:
        base=.95 if height<12 else 1.35
        for i in range(3):
            y0=.3+(height*.78-.3)*i/3; y1=.3+(height*.78-.3)*(i+1)/3
            radius0=base*(1-.28*i/3); radius1=base*(1-.28*(i+1)/3)
            a.mesh.cone((0,y0,0),(0,y1,0),radius0,radius1,color if i!=1 else "white",8)
    y=height*.8
    a.mesh.cylinder((0,y-.12,0),(0,y+.08,0),1.5 if height>=10 else 1.1,"concrete",8)
    for i in range(4):
        t=i*math.pi/2; x,z=1.3*math.cos(t),1.3*math.sin(t)
        if height>=10: a.mesh.beam((x,y,z),(x,y+.9,z),.07,.07,"steel")
    a.mesh.cylinder((0,y+.1,0),(0,height-.6,0),.65,"glass",8)
    a.mesh.cone((0,height-.6,0),(0,height,0),1,.2,color,8)
    a.mesh.cylinder((0,y+.4,0),(0,y+.7,0),.69,lens,8)
    a.mesh.box((0,1,.98),(.6,1.5,.05),"dark")
    a.marker("LightSocket",(0,y+.55,0),"navigation_light")
    a.box_collision((0,height*.4,0),(1.8,height*.8,1.8))
    a.extra.update(height_m=height,navigation_light_color=lens,light_node_default_enabled=False,light_range_m=16,real_port_light_assignment="unassigned")
    return a


def build():
    specs=[("lighthouse_red","적색 원통 등대",10,"round","red","lens_red"),
           ("lighthouse_green","녹색 원통 등대",10,"round","green","lens_green"),
           ("lighthouse_white_tall","백색 높은 등대",16,"round","white","lens_warm"),
           ("lighthouse_square","사각 등대",12,"square","white","lens_warm"),
           ("lighthouse_lattice","골조형 소형 등대",7,"lattice","steel","lens_warm"),
           ("beacon_short","짧은 방파제 표지등",4,"round","red","lens_red")]
    return [build_one(*spec) for spec in specs]
