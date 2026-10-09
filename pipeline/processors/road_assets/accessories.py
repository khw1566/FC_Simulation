"""교차로·폭 전환·경계 부재와 독립 노면 표시 생성."""
import math
from road_assets.mesh import RoadMesh
from road_assets.profiles import LENGTH, LANE_WIDTH, WALK_HEIGHT, profile, port, WALK_TYPES
from road_assets.surfaces import pattern


def junction(kind, style, lanes=0, shape="cross"):
    walk=kind=="walk"; width=3.0 if walk else lanes*LANE_WIDTH+1
    height=WALK_HEIGHT if walk else 0; extent=width/2+LENGTH/2
    material=WALK_TYPES[style][1] if walk else "asphalt"
    mode=WALK_TYPES[style][2] if walk else "plain"
    mesh=RoadMesh(); cross=profile("walk" if walk else "vehicle",width,lanes,height)
    ports=[]
    def slab(cx,cz,w,length,angle=0):
        a=(cx-math.sin(angle)*length/2,cz-math.cos(angle)*length/2,angle)
        b=(cx+math.sin(angle)*length/2,cz+math.cos(angle)*length/2,angle)
        mesh.strip([a,b],-w/2,w/2,height,"joint" if walk else material,
                   0 if walk else -.18)
        if walk: pattern(mesh,[a,b],w,height,material,mode)
    slab(0,0,width,width)
    for name,(dx,dz) in {"North":(0,-1),"South":(0,1),"East":(1,0),"West":(-1,0)}.items():
        if name=="West" and shape=="tee": continue
        center=width/2+LENGTH/4
        slab(dx*center,dz*center,width,LENGTH/2,math.pi/2 if dx else 0)
        ports.append(port(name,(dx*extent,height,dz*extent),(dx,0,dz),cross))
    return mesh,ports,{"width":width,"lanes":lanes,"shape":shape,"style":style,"kind":kind}


def transition(kind, start_width, end_width, start_height=0, end_height=0,
               start_lanes=0, end_lanes=0):
    mesh=RoadMesh(); z=LENGTH/2; bottom=-.18 if kind=="vehicle" else -.03
    vertices=[(-start_width/2,bottom,-z),(start_width/2,bottom,-z),
              (start_width/2,start_height,-z),(-start_width/2,start_height,-z),
              (-end_width/2,bottom,z),(end_width/2,bottom,z),
              (end_width/2,end_height,z),(-end_width/2,end_height,z)]
    for indices in ((0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)):
        mesh.quad(*(vertices[i] for i in indices),"asphalt" if kind=="vehicle" else "concrete")
    ports=[port("Start",(0,start_height,-z),(0,0,-1),profile(kind,start_width,start_lanes,start_height)),
           port("End",(0,end_height,z),(0,0,1),profile(kind,end_width,end_lanes,end_height))]
    return mesh,ports


def accessory(key):
    mesh=RoadMesh(); ports=[]
    if key.startswith("curb_"):
        height=.08 if key=="curb_mountable" else .15
        mesh.box((0,height/2,0),(.2,height,LENGTH),"concrete")
        for z in range(-5,6): mesh.box((0,height+.001,z),(.20,.002,.015),"joint")
        if key=="curb_drain":
            for z in (-4,0,4): mesh.box((-.101,.05,z),(.003,.065,.5),"joint")
        cross=profile("curb",.2,0,height)
        ports=[port("Start",(0,height,-6),(0,0,-1),cross),port("End",(0,height,6),(0,0,1),cross)]
    elif key in ("railing", "guardrail", "bollards"):
        for z in (-6,-3,0,3,6):
            mesh.cylinder((0,0,z),(0,1.1,z),.065 if key!="bollards" else .12,"steel",8)
        if key=="railing":
            for y in (.4,.8,1.1): mesh.beam((0,y,-6),(0,y,6),.06,.06,"steel")
        if key=="guardrail": mesh.box((0,.75,0),(.12,.28,LENGTH),"steel")
    elif key=="planter_strip":
        mesh.box((0,.10,0),(1.5,.2,LENGTH),"earth_dark")
        mesh.box((0,.203,0),(1.35,.006,LENGTH),"grass")
        for x in (-.71,.71): mesh.box((x,.13,0),(.08,.26,LENGTH),"concrete")
    elif key=="drain_channel":
        mesh.box((0,.005,0),(.5,.01,LENGTH),"steel")
        for i in range(60): mesh.box((0,.011,-5.9+i*.2),(.44,.002,.055),"joint")
    elif key in ("tactile_warning","tactile_guide"):
        width,length=(3,1.2) if key=="tactile_warning" else (.4,LENGTH)
        mesh.box((0,.004,0),(width,.008,length),"yellow")
        if key=="tactile_warning":
            for i in range(20):
                for j in range(8): mesh.cylinder((-1.425+i*.15,.008,-.525+j*.15),
                    (-1.425+i*.15,.012,-.525+j*.15),.035,"yellow",6)
        else:
            for x in (-.14,0,.14): mesh.box((x,.012,0),(.025,.008,LENGTH),"yellow")
    elif key=="steps":
        for i in range(10): mesh.box((0,.15*(i+1)/2,-6+(i+.5)*1.2),(3,.15*(i+1),1.2),"concrete")
        ports=[port("Start",(0,.15,-6),(0,0,-1),profile("walk",3,0,.15)),
               port("End",(0,1.5,6),(0,0,1),profile("walk",3,0,1.5))]
    return mesh,ports


def decal(key):
    mesh=RoadMesh(); y=.004
    if key in ("solid_white","solid_yellow","dashed_white","double_yellow"):
        color="yellow" if "yellow" in key else "white"
        for x in ((-.12,.12) if key=="double_yellow" else (0,)):
            if key=="dashed_white":
                for z in (-4,0,4): mesh.patch((x,z,0),0,.12,2,y,color)
            else: mesh.patch((x,0,0),0,.12,LENGTH,y,color)
    elif key=="zebra_crossing":
        for x in (-3,-2,-1,0,1,2,3): mesh.patch((x,0,0),0,.5,3,y,"white")
    elif key=="stop_line": mesh.patch((0,0,math.pi/2),0,.35,3.25,y,"white")
    elif key.startswith("arrow_"):
        mesh.patch((0,0,0),0,.18,2.2,y,"white")
        mesh.triangle((-.65,y,.75),(0,y,1.75),(.65,y,.75),"white")
        if key in ("arrow_left","arrow_right"):
            sign=-1 if key=="arrow_left" else 1
            mesh.patch((sign*.6,.4,math.pi/2),0,.18,1.2,y,"white")
            a=(sign*1.2,y,-.1); b=(sign*1.2,y,.9); c=(sign*1.9,y,.4)
            mesh.triangle(*( (a,b,c) if sign==1 else (b,a,c)),"white")
    elif key=="cycle_symbol":
        for cx in (-.65,.65):
            for i in range(16):
                a=i*math.pi/8; b=(i+1)*math.pi/8
                p=lambda r,t:(cx+r*math.cos(t),y,r*math.sin(t))
                mesh.quad(p(.28,a),p(.28,b),p(.35,b),p(.35,a),"white")
        mesh.beam((-.65,y,0),(0,y,.55),.05,.004,"white")
        mesh.beam((0,y,.55),(.65,y,0),.05,.004,"white")
    return mesh


ACCESSORIES={"curb_straight":"일반 경계석","curb_mountable":"낮은 경계석",
    "curb_drain":"배수구 경계석","railing":"보행 난간","guardrail":"차량 방호울타리",
    "bollards":"보행 분리 볼라드","planter_strip":"녹지 띠","drain_channel":"선형 배수 덮개",
    "tactile_warning":"점자 경고블록","tactile_guide":"점자 유도블록","steps":"보행 계단"}
DECALS={"solid_white":"백색 실선","solid_yellow":"황색 실선","dashed_white":"백색 점선",
    "double_yellow":"황색 이중선","zebra_crossing":"횡단보도","stop_line":"정지선",
    "arrow_forward":"직진 화살표","arrow_left":"직진·좌회전 화살표",
    "arrow_right":"직진·우회전 화살표","cycle_symbol":"자전거 표시"}
