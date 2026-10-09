"""서로 다른 차선 수를 연결하는 교차로 중심·진입·표시 모듈."""
import math
from road_assets.mesh import RoadMesh
from road_assets.profiles import LANE_WIDTH, profile, port
from road_assets.low_detail import surface_lines

PAIRS=((2,2),(4,2),(4,4),(6,2),(6,4),(8,4))
DIRECTIONS={"North":(0,-1),"South":(0,1),"East":(1,0),"West":(-1,0)}


def width(lanes): return lanes*LANE_WIDTH+1


def core(main_lanes, branch_lanes, shape):
    mesh=RoadMesh(); w,d=width(main_lanes),width(branch_lanes)
    mesh.box((0,-.09,0),(w,.18,d),"asphalt")
    ports=[]
    for name,(x,z) in DIRECTIONS.items():
        if name=="West" and shape=="tee": continue
        lanes=branch_lanes if x else main_lanes
        ports.append(port(name,(x*w/2,0,z*d/2),(x,0,z),profile("vehicle",width(lanes),lanes,0)))
    return mesh,ports


def approach(lanes, material):
    mesh=RoadMesh(); w=width(lanes)
    mesh.strip([(0,-3,0),(0,3,0)],-w/2,w/2,0,material,-.18)
    if material=="paver_gray": surface_lines(mesh,[(0,-3,0),(0,3,0)],w,0,material,"large_slabs")
    ports=[port("Start",(0,0,-3),(0,0,-1),profile("vehicle",w,lanes,0)),
           port("End",(0,0,3),(0,0,1),profile("vehicle",w,lanes,0))]
    return mesh,ports


def approach_marking(lanes):
    mesh=RoadMesh()
    for offset in (-lanes*LANE_WIDTH/2,lanes*LANE_WIDTH/2):
        mesh.patch((offset,0,0),0,.12,6,.006,"white")
    for i in range(1,lanes):
        for z in (-1.5,2): mesh.patch(((i-lanes/2)*LANE_WIDTH,z,0),0,.12,1.2,.006,"white")
    return mesh


def crossing_overlay(main_lanes, branch_lanes, shape):
    mesh=RoadMesh(); w,d=width(main_lanes),width(branch_lanes)
    for name,(dx,dz) in DIRECTIONS.items():
        if name=="West" and shape=="tee": continue
        span=width(branch_lanes if dx else main_lanes)-1
        outer=w/2 if dx else d/2
        center=outer+1.8
        angle=math.pi/2 if dx else 0
        # 횡단보도 줄무늬는 차선 영역의 폭 안에 배치한다.
        count=max(2,min(8,math.floor(span/1.3))); pitch=span/count
        for i in range(count):
            p=(dx*center,dz*center,angle)
            mesh.patch(p,-span/2+(i+.5)*pitch,pitch*.52,2.2,.008,"white")
    return mesh


def models():
    for main,branch in PAIRS:
        for shape in ("tee","cross"):
            mesh,ports=core(main,branch,shape)
            key=f"mix_junction_{main}l_{branch}l_{shape}_core"
            info={"kind":"junction_core","main_lanes":main,"branch_lanes":branch,"shape":shape,
                  "assembly_part":"center_only","approach_length_m":6,"surface_material":"asphalt"}
            yield key,f"{main}차선×{branch}차선 / {'T자' if shape=='tee' else '십자'} 중앙부",mesh,ports,info
            yield key.replace("_core","_crossings"),f"{main}·{branch}차선 교차로 / 횡단 표시",crossing_overlay(main,branch,shape),[],{
                "kind":"junction_marking","main_lanes":main,"branch_lanes":branch,"shape":shape,
                "assembly_part":"crossing_overlay","placement_y_m":0,"requires_approaches":True}
    for lanes in (2,4,6,8):
        for material,label in (("asphalt","아스팔트"),("concrete","콘크리트"),("paver_gray","블록")):
            mesh,ports=approach(lanes,material)
            yield f"mix_approach_{lanes}l_{material}",f"{lanes}차선 / {label} 진입부",mesh,ports,{
                "kind":"junction_approach","lanes":lanes,"width":width(lanes),"length_m":6,
                "material":material,"assembly_part":"approach","suggested_marking":f"mix_approach_{lanes}l_markings"}
        yield f"mix_approach_{lanes}l_markings",f"{lanes}차선 진입부 / 표시",approach_marking(lanes),[],{
            "kind":"junction_marking","lanes":lanes,"placement_y_m":0,"assembly_part":"approach_overlay"}
