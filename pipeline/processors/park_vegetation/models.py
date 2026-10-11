"""범용 군락의 형태와 LOD 제원. 실제 종·품종을 주장하지 않는다."""
import math
import random
from .geometry import ParkMesh

SPECS={
    "grass_sparse":("성긴 짧은 풀","grass",[20,60],.55),
    "grass_dense":("조밀한 짧은 풀","grass",[20,60],.75),
    "flower_low_round":("낮은 꽃무리","flower",[35,100,250],1.4),
    "flower_low_edge":("꽃길 가장자리 군락","flower",[35,100,250],1.6),
    "perennial_upright":("직립 초화 군락","perennial",[40,120,350],1.5),
    "perennial_dry":("마른 꽃대 군락","perennial",[40,120,350],1.5),
    "ornamental_fine":("가는 잎 관상용 풀","ornamental",[40,120,350],1.3),
    "ornamental_seedhead":("이삭형 관상용 풀","ornamental",[40,120,350],1.5),
    "hedge_1m":("생울타리 1m","hedge",[60,180,500],1),
    "hedge_2m":("생울타리 2m","hedge",[60,180,500],2),
    "hedge_4m":("생울타리 4m","hedge",[60,180,500],4),
    "hedge_corner":("생울타리 모서리","hedge",[60,180,500],2),
    "hedge_end":("생울타리 끝단","hedge",[60,180,500],1),
    "rock_small":("작은 조경석","rock",[60,180,400],.75),
    "rock_medium":("중간 조경석","rock",[60,180,400],1.5),
    "rock_cluster":("조경석 군락","rock",[60,180,400],2.2),
}


def build(key,lod):
    m=ParkMesh()
    label,kind,distances,width=SPECS[key]
    rng=random.Random(310+list(SPECS).index(key))
    if kind=="hedge": hedge(m,key,lod)
    elif kind=="rock":
        count=3 if key=="rock_cluster" and lod<2 else 1
        for i in range(count):
            size=width if count==1 else width*.52
            x,z=((i-1)*.62,(-1)**i*.25) if count>1 else (0,0)
            m.rock((x,0,z),(size,size*.65,size*.8),[8,6,4][lod],[3,2,1][lod],i)
    elif kind=="grass":
        count=([12,4] if key=="grass_sparse" else [20,6])[lod]
        for i in range(count):
            x,z=rng.uniform(-width/2,width/2),rng.uniform(-width/2,width/2)
            m.blade((x,0,z),rng.uniform(.16,.32),.045,rng.random()*math.tau,.1)
    elif kind=="ornamental":
        count=[20,8,3][lod]
        for i in range(count):
            angle=rng.random()*math.tau
            x,z=rng.uniform(-.2,.2),rng.uniform(-.2,.2)
            h=rng.uniform(.45,.85)
            m.blade((x,0,z),h,.07,angle,.35,"light_leaf")
            if key=="ornamental_seedhead" and lod==0 and i%4==0:
                m.bloom((x+math.cos(angle)*.35,h,z+math.sin(angle)*.35),.045,"dry",.13)
    else:
        count=([6,3,2] if kind=="flower" else [5,2,1])[lod]
        dry=key.endswith("dry")
        for i in range(count):
            x=rng.uniform(-width*.38,width*.38)
            z=rng.uniform(-width*.3,width*.3)
            if key.endswith("edge"): z=abs(z)*.45
            h=rng.uniform(.22,.38) if kind=="flower" else rng.uniform(.65,1.15)
            if lod<2:
                m.cylinder((x,0,z),(x,h,z),.012,"dry" if dry else "stem",3)
                for angle in ([0,2] if lod==0 else [0]):
                    m.blade((x,h*.2,z),h*.35,.12,angle+i,.16,"dry" if dry else "leaf")
            m.bloom((x,h,z),.12 if kind=="flower" else .065,
                    "dry" if dry else "pink" if key.endswith("edge") else "flower",.06 if kind=="flower" else .11)
    return m


def hedge(m,key,lod):
    length={"hedge_1m":1,"hedge_2m":2,"hedge_4m":4,"hedge_corner":2,"hedge_end":1}[key]
    if lod==2:
        m.box((0,.5,0),(.6,1,length),"leaf")
    else:
        slices=3 if lod==0 else 1
        for i in range(slices):
            z0=-length/2+length*i/slices; z1=-length/2+length*(i+1)/slices
            h=1+(0.03*math.sin(i*2) if lod==0 else 0)
            m.profile([(-.3,0),(.3,0),(.3,h*.75),(.2,h),(-.2,h),(-.3,h*.75)],z1,z0,"leaf")
    if key=="hedge_corner":
        # L자 가지를 별도 생성하고 바깥쪽 연결 포트를 제공한다.
        m.box((.5,.5,.7),(1.6,1,.6),"leaf")


def ports(key):
    if not key.startswith("hedge_"): return []
    length=SPECS[key][3]
    result=[{"position":[0,0,-length/2],"direction":[0,0,-1],"profile":"park_hedge_w060_h100"}]
    if key=="hedge_corner":
        result.append({"position":[1.3,0,.7],"direction":[1,0,0],"profile":"park_hedge_w060_h100"})
    elif key!="hedge_end":
        result.append({"position":[0,0,length/2],"direction":[0,0,1],"profile":"park_hedge_w060_h100"})
    return result
