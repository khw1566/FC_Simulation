"""28개 원본 설비의 주요 체적과 실루엣을 원경용으로 구성한다."""
from .geometry import DistantMesh


def build(key,level):
    m=DistantMesh(level)
    if key.startswith("factory_") or key=="shipbuilding_hangar":
        factory(m,key)
    elif key.startswith("pipeline_") or key.startswith("rack_"):
        pipe(m,key)
    elif key in ("tower_crane","gantry_crane","transmission_tower","flare_lattice"):
        structure(m,key)
    elif key=="cooling_fan_bank":
        m.box((0,2.85,0),(29,5.7,17))
        for x in (-9,0,9):
            for z in (-4,4):
                m.cylinder((x,5.7,z),(x,6.4,z),2.3)
    elif key=="cooling_tower":
        levels=[(0,20.14),(4,20.14),(20,12),(34,10),(50,12.94)]
        if level==2: levels=[levels[0],levels[3],levels[-1]]
        m.shell((0,0),levels,False)
    elif key=="lpg_sphere":
        m.box((0,.3,0),(25,.6,25))
        for x in (-4.5,4.5):
            for z in (-4.5,4.5): m.box((x,4.5,z),(.9,9,.9))
        m.sphere((0,13,0),9)
        m.cylinder((0,22,0),(0,23.4,0),.5)
    elif key=="liquid_storage_tank":
        m.cylinder((0,0,0),(0,.7,0),17)
        m.shell((0,0),[(.7,16),(16.7,16),(18.7,.4)])
        m.cylinder((16,1.7,0),(19,1.7,0),.4)
    else:
        tower(m,key)
    # 단일 표면과 무광 단색 재질로 원경 드로콜을 줄인다.
    return m


def factory(m,key):
    w,l,h={"factory_gable":(48,72,12),"factory_sawtooth":(64,88,10),
           "factory_flat":(44,60,16),"shipbuilding_hangar":(100,180,42)}[key]
    m.box((0,.3,0),(w+2,.6,l+2))
    if key=="shipbuilding_hangar":
        for x in (-w/2,w/2): m.box((x,h/2,0),(1,h,l))
        m.box((0,h/2,-l/2),(w,h,1))
        m.box((0,h-4,l/2),(w,8,1))
        m.profile([(-51,42),(51,42),(0,52)],91,-91)
    else:
        m.box((0,h/2+.6,0),(w,h,l))
        if key=="factory_gable":
            m.profile([(-w/2,h+.6),(w/2,h+.6),(0,h+6)],l/2+1,-l/2-1)
        elif key=="factory_sawtooth":
            count=8 if m.level==1 else 4
            for i in range(count):
                a=-w/2+i*w/count; b=a+w/count
                m.profile([(a,h+.6),(b,h+.6),(b,h+4.6)],l/2+1,-l/2-1)
        else:
            m.box((0,h+.9,0),(w+1,.6,l+1))
            m.box((0,h+2,0),(30,2.2,10))


def tower(m,key):
    dimensions={"distillation_tower":(41,3.2,3.2),"industrial_chimney":(65,4.4,2.8),
                "stack_concrete":(90,5.1,2.6),"stack_steel":(55,2.4,1.6),
                "stack_triple":(62,1.7,1.25),"process_column":(51,3.4,3.4),
                "scrubber_tower":(38,1.4,1.4)}
    h,r,t=dimensions[key]
    m.box((0,.4,0),(16,.8,16))
    for x in ((-4,0,4) if key=="stack_triple" else (0,)):
        if key in ("process_column","distillation_tower"):
            m.shell((x,0),[(.8,r),(h-2,r),(h,.4)])
        else: m.shell((x,0),[(0,r),(h,t)])
    if key=="scrubber_tower":
        m.shell((0,0),[(.8,4.2),(25,4.2),(27,1.4)])
    if key in ("distillation_tower","process_column") and m.level==1:
        for y in (h*.25,h*.5,h*.75):
            m.cylinder((0,y,0),(0,y+.3,0),r+1)
    if key.startswith("stack_") or key in ("process_column","scrubber_tower"):
        m.beam((-12,5,0),(0,5,0),1,2.8)


def structure(m,key):
    if key=="tower_crane":
        m.box((0,.5,0),(10,1,10))
        m.box((0,28,0),(3,54,3))
        m.box((21,55,0),(78,2.5,2.5))
        m.box((-13,54,0),(8,3,4))
        m.box((2.5,53,2.1),(4,3,3))
        m.beam((0,55,0),(0,65,0),.4,.4)
        for x in (-18,52): m.beam((0,65,0),(x,56,0),.16,.16)
        if m.level==1:
            m.beam((35,53,0),(35,20,0),.15,.15)
            m.box((35,19,0),(1.5,2,1))
    elif key=="gantry_crane":
        for x in (-42,42):
            m.box((x,1,0),(12,2,34))
            for z in (-12,12): m.beam((x,2,z),(x*.9,52,z*.3),2.2,2.2)
        for z in (-4,4): m.box((0,54,z),(96,4,4))
        m.box((10,53,0),(10,3,13))
        if m.level==1:
            for x in (7,13): m.beam((x,51,0),(x,18,0),.18,.18)
            m.box((10,18,0),(9,1.5,6))
    else:
        top=46 if key=="transmission_tower" else 66
        radius=7 if key=="transmission_tower" else 5
        for x in (-1,1):
            for z in (-1,1):
                m.beam((x*radius,0,z*radius),(x*.6,top,z*.6),.5,.5)
        if m.level==1:
            for y in (0,top/3,top*2/3):
                r=radius+(0.6-radius)*y/top; s=radius+(0.6-radius)*(y+top/3)/top
                for z in (-1,1): m.beam((-r,y,z*r),(s,y+top/3,z*s),.25,.25)
        if key=="transmission_tower":
            for y,span in ((25,12),(33,10),(40,8)): m.box((0,y,0),(span*2,.5,1.4))
        else: m.shell((0,0),[(0,1.2),(72,.75)])


def pipe(m,key):
    kind=key.replace("pipeline_","").replace("rack_","")
    lanes=(-1.1,0,1.1) if m.level==1 else (0,)
    radius=.32 if m.level==1 else 1.42
    paths=[]
    for z in lanes:
        if kind=="elbow":
            paths.append([(-12,5,z),(-4,5,z),(-1+z*.5,5,1),(z,5,4),(z,5,12)])
        elif kind=="riser": paths.append([(-12,5,z),(-4,5,z),(4,9,z),(12,9,z)])
        else:
            paths.append([(-12,5,z),(12,5,z)])
            if kind=="double": paths.append([(-12,9,z),(12,9,z)])
            if kind in ("tee","cross"):
                paths.append([(z,5,-12 if kind=="cross" else 0),(z,5,12)])
    for points in paths:
        for a,b in zip(points,points[1:]):
            if m.level==1: m.cylinder(a,b,radius)
            else: m.beam(a,b,2.84,.64)
    supports=[(-9,0),(9,0)] if kind!="elbow" else [(-9,0),(0,9)]
    if kind in ("tee","cross"): supports.append((0,9))
    if kind=="cross": supports.append((0,-9))
    for x,z in supports:
        h=9 if kind=="double" or kind=="riser" and x>0 else 5
        branch=x==0
        if m.level==1:
            for offset in (-1.8,1.8):
                m.box((x+offset if branch else x,h/2,z if branch else z+offset),(.3,h,.3))
            m.box((x,h-.4,z),(4.2,.3,.4) if branch else (.4,.3,4.2))
        else:
            m.box((x,h/2,z),(3.8,h,.4) if branch else (.4,h,3.8))
