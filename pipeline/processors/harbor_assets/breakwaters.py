"""직선·곡선 방파제와 개별 테트라포드. 상부와 기초를 분리한다."""
import math
from .asset import HarborAsset


def straight(length,wall=True):
    key=f"breakwater_straight_{length}m"+("_open" if not wall else "")
    a=HarborAsset(key,f"콘크리트 방파제 {length}m"+(" 개방형" if not wall else ""),"breakwater")
    a.mesh.box((0,-.3,0),(4,.6,length),"concrete")
    if wall: a.mesh.box((1.65,.65,0),(.7,1.3,length),"concrete_dark")
    a.ends(length,4,"breakwater_4m"); a.box_collision((0,-.3,0),(4,.6,length))
    if wall: a.box_collision((1.65,.65,0),(.7,1.3,length))
    a.extra.update(length_m=length,width_m=4,foundation_separate=True)
    return a


def curve(degrees):
    angle=math.radians(degrees); radius=12; segments=3 if degrees==45 else 6
    a=HarborAsset(f"breakwater_curve_{degrees}",f"방파제 곡선 {degrees}도","breakwater")
    def point(t,offset,y): return (radius*(1-math.cos(t))+offset*math.cos(t),y,radius*math.sin(t))
    for i in range(segments):
        t,u=angle*i/segments,angle*(i+1)/segments
        polygon=[point(t,-2,0),point(u,-2,0),point(u,2,0),point(t,2,0)]
        a.mesh.slab([(p[0],p[2]) for p in polygon],0,-.6)
        a.convex_collision([(p[0],y,p[2]) for p in polygon for y in (0,-.6)])
        center0,center1=point(t,1.65,.65),point(u,1.65,.65)
        a.mesh.beam(center0,center1,.7,1.3,"concrete_dark")
        wall=[point(t,d,y) for d in (1.3,2) for y in (0,1.3)]+[point(u,d,y) for d in (1.3,2) for y in (0,1.3)]
        a.convex_collision(wall)
    a.marker("Start",(0,0,0),"breakwater_4m",(0,0,-1),4)
    a.marker("End",point(angle,0,0),"breakwater_4m",(math.sin(angle),0,math.cos(angle)),4)
    a.extra.update(radius_m=radius,angle_degrees=degrees,foundation_separate=True)
    return a


def head():
    a=HarborAsset("breakwater_head","방파제 등대 설치 끝단","breakwater")
    a.mesh.box((0,-.3,0),(6,.6,6),"concrete")
    a.mesh.box((0,.6,2.65),(6,1.2,.7),"concrete_dark")
    for x in (-2.65,2.65): a.mesh.box((x,.6,0),(.7,1.2,6),"concrete_dark")
    a.marker("Start",(0,0,-3),"breakwater_4m",(0,0,-1),4)
    a.marker("LighthouseMount",(0,0,0),"facility_base")
    a.box_collision((0,-.3,0),(6,.6,6)); a.extra["foundation_separate"]=True
    return a


def junction():
    a=HarborAsset("breakwater_junction_t","방파제 T 분기","breakwater")
    a.mesh.box((0,-.3,0),(4,.6,4),"concrete")
    for name,point,direction in (("West",(-2,0,0),(-1,0,0)),("East",(2,0,0),(1,0,0)),("South",(0,0,-2),(0,0,-1))):
        a.marker(name,point,"breakwater_4m",direction,4)
    a.mesh.box((0,.65,1.65),(4,1.3,.7),"concrete_dark"); a.box_collision((0,-.3,0),(4,.6,4))
    return a


def tetrapod(size):
    a=HarborAsset(f"tetrapod_{size}m",f"테트라포드 단위 {size}m","armor","terrain_bottom")
    radius=size/3.2
    directions=[(0,1,0)]+[(math.sqrt(8/9)*math.cos(t),-1/3,math.sqrt(8/9)*math.sin(t)) for t in (0,math.tau/3,math.tau*2/3)]
    for d in directions:
        a.mesh.cone(tuple(v*radius*.1 for v in d),tuple(v*radius*1.7 for v in d),radius*.55,radius*.27,"concrete",6)
    bottom=min(p[1] for face in a.mesh.faces for p in face[:3])
    a.mesh.faces=[(*[(p[0],p[1]-bottom,p[2]) for p in f[:3]],f[3],f[4]) for f in a.mesh.faces]
    a.marker("MassCenter",(0,-bottom,0),"armor_center")
    a.extra.update(instancing_recommended=True,physics_default=False,rotation_policy="rotate_then_reanchor_lowest_point",nominal_size_m=size)
    return a


def build():
    return [straight(n) for n in (6,12,24)]+[straight(12,False),curve(45),curve(90),head(),junction()]+[tetrapod(n) for n in (1.5,2.5,4)]
