"""송전탑, 냉각설비, 조선용 대형 격납고의 정적 외관."""

import math
from .geometry import IndustrialMesh


def build(kind):
    mesh = IndustrialMesh()
    if kind == 'transmission_tower':
        levels = [(0,7),(10,5),(22,3),(34,1.8),(46,.6)]
        for (y,r),(top,s) in zip(levels,levels[1:]):
            for x,z in ((-1,-1),(-1,1),(1,1),(1,-1)):
                mesh.beam((x*r,y,z*r),(x*s,top,z*s),.32,.32,'steel')
                mesh.beam((x*r,y,z*r),(-x*s,top,z*s),.18,.18,'steel')
                mesh.beam((x*r,y,z*r),(x*s,top,-z*s),.18,.18,'steel')
        for y,span in ((25,12),(33,10),(40,8)):
            mesh.box((0,y,0),(span*2,.45,1.4),'steel')
            for x in (-span,span):
                mesh.beam((0,y+4,0),(x,y,0),.23,.23,'steel')
                mesh.cylinder((x,y-2.5,0),(x,y,0),.25,'white',10)
                for j in range(8): mesh.cylinder((x,y-2.4+j*.3,0),(x,y-2.3+j*.3,0),.4,'white',10)
        for x in (-7,7):
            for z in (-7,7): mesh.box((x,.4,z),(3,.8,3),'deck')
    elif kind == 'cooling_tower':
        rows,segments=16,32
        def point(row,col):
            t=row/rows; radius=10+24*(t-.65)**2
            a=col*math.tau/segments
            return (radius*math.cos(a),4+t*46,radius*math.sin(a))
        for row in range(rows):
            for col in range(segments):
                a,b,c,d=point(row,col),point(row+1,col),point(row+1,col+1),point(row,col+1)
                mesh.quad(a,b,c,d,'white')
                mesh.quad(d,c,b,a,'deck')
        for i in range(16):
            a=i*math.tau/16; r=20.14
            mesh.beam((r*math.cos(a),0,r*math.sin(a)),point(0,i*2),.8,.8,'steel')
        mesh.cylinder((0,0,0),(0,.4,0),22,'deck',32)
    elif kind == 'cooling_fan_bank':
        mesh.box((0,.3,0),(29,.6,17),'deck')
        for x in (-9,0,9):
            for z in (-4,4):
                mesh.box((x,3,z),(7,5.4,6),'white')
                mesh.cylinder((x,5.7,z),(x,6,z),2.3,'dark',24)
                mesh.cylinder((x,6,z),(x,6.4,z),.4,'steel',12)
                for a in (0,math.pi/2):
                    mesh.beam((x-1.9*math.cos(a),6.15,z-1.9*math.sin(a)),
                              (x+1.9*math.cos(a),6.15,z+1.9*math.sin(a)),.45,.12,'steel')
                for y in (1,2,3,4): mesh.box((x,y,z+3.04),(6,.12,.12),'dark')
    elif kind == 'shipbuilding_hangar':
        mesh.box((0,.4,0),(104,.8,184),'deck')
        for x in (-50,50): mesh.box((x,21,0),(1,42,180),'white')
        mesh.box((0,21,-90),(100,42,1),'white')
        mesh.box((0,38,90),(100,8,1),'white')
        for x in (-43,43): mesh.box((x,17,90),(14,34,1),'steel')
        mesh.profile([(-51,42),(51,42),(0,52)],91,-91,'steel')
        for z in range(-84,85,12):
            for x in (-49,49): mesh.box((x,21,z),(1.2,42,1.2),'steel')
        for x in (-50.6,50.6): mesh.box((x,31,0),(.2,3,168),'glass')
    else:
        raise ValueError(kind)
    return mesh
