"""차도·보행로 표면과 패턴 생성."""
import math
from road_assets.mesh import RoadMesh
from road_assets.profiles import WALK_HEIGHT, LANE_WIDTH, route, route_ports, profile


def sample(points, distance):
    for a,b in zip(points,points[1:]):
        length=math.hypot(b[0]-a[0],b[1]-a[1])
        if distance<=length:
            t=distance/length
            return tuple(a[i]+(b[i]-a[i])*t for i in range(3))
        distance-=length
    return points[-1]


def path_length(points):
    return sum(math.hypot(b[0]-a[0],b[1]-a[1]) for a,b in zip(points,points[1:]))


def pattern(mesh, points, width, top, material, mode):
    length=path_length(points)
    if mode=="plain": return
    if mode=="shared":
        mesh.strip(points,0-.04,0+.04,top+.002,"white")
        return
    if mode=="tactile":
        mesh.strip(points,-.2,.2,top+.002,"yellow")
        for i in range(3): mesh.strip(points,-.14+i*.14,-.115+i*.14,top+.009,"yellow")
        return
    if mode in ("earth","gravel"):
        for i in range(int(length/.45)):
            p=sample(points,.2+i*.45)
            for j in range(3):
                offset=(j-1)*width*.27+math.sin(i*7+j*3)*.07
                mesh.patch(p,offset,.07 if mode=="gravel" else .14,.09,top+.002,
                           material+"_light" if (i+j)%3==0 else material+"_dark")
        return
    sizes={"slabs":(.75,1.0),"large_slabs":(1.5,1.5),"pavers":(.3,.6),
           "bricks":(.25,.5),"diagonal":(.35,.35),"cobbles":(.28,.35),
           "permeable":(.3,.6),"wood_long":(.20,2.0),"wood_cross":(width,.25)}
    tw,tl=sizes[mode]
    columns=max(1,round(width/tw)); step=width/columns
    rows=max(1,round(length/tl)); spacing=length/rows
    for i in range(rows):
        p=sample(points,(i+.5)*spacing)
        for j in range(columns):
            center=-width/2+(j+.5)*step
            gap=.04 if mode=="permeable" else .024
            color=material+"_light" if (i*13+j*7)%7==0 else material+"_dark" if (i+j)%11==0 else material
            tile_w=step-gap; tile_l=spacing-gap
            if mode=="diagonal":
                # 사선 타일은 각 패턴 셀 내부에 배치한다.
                tile_w=tile_l=min(step,spacing)/math.sqrt(2)-gap
                q=mesh.at(p,center,top)
                mesh.patch((q[0],q[2],p[2]+math.pi/4),0,tile_w,tile_l,top+.002,color)
            elif mode=="bricks":
                start=-width/2; end=width/2
                shift=step/2 if i%2 else 0
                # 행의 양 끝을 잘라 연결 폭을 유지한다.
                for left in [start-step+shift+k*step for k in range(columns+2)]:
                    lo=max(start,left); hi=min(end,left+step)
                    if hi-lo>gap:
                        a=sample(points,i*spacing+gap/2); b=sample(points,(i+1)*spacing-gap/2)
                        mesh.strip([a,b],lo+gap/2,hi-gap/2,top+.002,color)
                break
            else:
                if mode=="cobbles": tile_w*=.88; tile_l*=.86
                a=sample(points,i*spacing+(spacing-tile_l)/2)
                b=sample(points,(i+1)*spacing-(spacing-tile_l)/2)
                mesh.strip([a,b],center-tile_w/2,center+tile_w/2,top+.002,color)


def build(spec):
    mesh=RoadMesh(); width=spec["width"]; points=route(spec["shape"],width)
    is_walk=spec["kind"]=="walk"; top=WALK_HEIGHT if is_walk else 0.0
    material=spec["material"]
    if is_walk and spec["pattern"] not in ("plain","earth","gravel","shared","tactile"):
        base="joint"
    else: base=material
    mesh.strip(points,-width/2,width/2,top,base,0 if is_walk else -.18)
    if is_walk: pattern(mesh,points,width,top,material,spec["pattern"])
    elif material in ("concrete","paver_gray"):
        for distance in range(3,int(path_length(points)),3):
            mesh.patch(sample(points,distance),0,width,.018,.002,"joint")
    cross=profile("walk" if is_walk else "vehicle",width,spec.get("lanes",0),top)
    return mesh,route_ports(points,cross)


def marking(lanes, shape):
    mesh=RoadMesh(); width=lanes*LANE_WIDTH+1; points=route(shape,width)
    for offset in (-lanes*LANE_WIDTH/2,lanes*LANE_WIDTH/2):
        mesh.strip(points,offset-.06,offset+.06,.004,"white")
    for line in range(1,lanes):
        offset=(line-lanes/2)*LANE_WIDTH
        for i in range(math.ceil(path_length(points)/4)):
            distance=i*4+1
            if distance+1<=path_length(points):
                mesh.patch(sample(points,distance),offset,.12,2,.004,"white")
    return mesh
