"""사진 참고 어선 인양 크레인과 컨테이너 크레인의 고정 포즈."""
from .asset import HarborAsset


def fishing(key,height,reach,hydraulic=False):
    a=HarborAsset(key,f"어선 인양 크레인 {reach}m"+(" 유압형" if hydraulic else " 기둥형"),"fishing_crane")
    a.mesh.box((0,.2,0),(2.8,.4,2.8),"concrete_dark")
    a.mesh.cylinder((0,.4,0),(0,height,0),.5 if hydraulic else .65,"red",8)
    if hydraulic:
        elbow=(reach*.35,height+2,0); tip=(reach,height,0)
        a.mesh.beam((0,height,0),elbow,.6,.5,"red"); a.mesh.beam(elbow,tip,.48,.4,"red")
        a.mesh.cylinder((0,height*.65,0),elbow,.16,"steel",6)
    else:
        tip=(reach,height+.4,0)
        a.mesh.beam((-2,height+.4,0),tip,.55,.5,"red")
        a.mesh.beam((0,height+3,0),(0,height,0),.4,.4,"red")
        for z in (-.2,.2): a.mesh.beam((0,height+3,z),(reach,height+.65,z),.045,.045,"dark")
        a.mesh.box((-1.8,height+.3,0),(1.8,1.3,1.6),"concrete_dark")
    a.mesh.box((reach*.65,height+.2,0),(1,.4,.8),"ochre")
    for z in (-.15,.15): a.mesh.beam((reach*.65,height,z),(reach*.65,2,z),.04,.04,"dark")
    a.mesh.box((reach*.65,1.75,0),(.45,.5,.45),"ochre")
    a.mesh.box((0,height*.5,.8),(1.8,.15,1.7),"steel")
    for x in (-.85,.85): a.mesh.beam((x,height*.5,1.55),(x,height*.5+1,1.55),.06,.06,"steel")
    a.marker("Hoist",(reach*.65,1.5,0),"hoist_attachment")
    a.marker("BoomTip",tip,"crane_envelope")
    a.box_collision((0,height/2,0),(1.3,height,1.3))
    a.extra.update(height_m=height+3 if not hydraulic else height+2,boom_reach_m=reach,sea_side_local_axis="+X",clearance_radius_m=reach,pose="static",reference_ko="첨부 사진의 기둥·수평 지브·상부 지지 케이블·인양장치 참고")
    return a


def container(key,height,span,rtg=False):
    a=HarborAsset(key,{"container_crane_feeder":"소형 컨테이너 이송 크레인","container_crane_sts":"안벽 컨테이너 이송 크레인","container_crane_rtg":"야드 컨테이너 갠트리"}[key],"container_crane")
    color="ochre" if rtg else "blue"
    for x in (-4,4):
        a.mesh.box((x,.35,0),(1.4,.7,12),"dark")
        for z in (-4.5,4.5):
            a.mesh.beam((x,.7,z),(x,height,z*.55),.8,.8,color)
            a.box_collision((x,height/2,z),(1,height,1))
    for z in (-2.5,2.5): a.mesh.beam((-4,height,z),(4,height,z),1,1,color)
    end=span if not rtg else 7
    a.mesh.beam((-8,height,0),(end,height,0),1.2,2,color)
    if not rtg:
        a.mesh.beam((0,height,0),(0,height+9,0),.6,.6,color)
        for z in (-.5,.5): a.mesh.beam((0,height+9,z),(end,height+.8,z),.07,.07,"dark")
        a.mesh.box((-6,height-.2,0),(5,2,4),"concrete_dark")
    a.mesh.box((3,height+1.2,0),(3,.7,3),"steel")
    for x in (2,4):
        for z in (-1,1): a.mesh.beam((x,height,z),(x,6,z),.04,.04,"dark")
    a.mesh.box((3,5.8,0),(2.5,.5,6),"yellow")
    a.mesh.box((4.5,height-1.5,3),(2,2,2),"glass")
    a.marker("Spreader",(3,5.4,0),"container_lift")
    a.marker("RailStart",(0,0,-6),"crane_rail_8m",(0,0,-1),8)
    a.marker("RailEnd",(0,0,6),"crane_rail_8m",(0,0,1),8)
    a.extra.update(rail_gauge_m=8,boom_reach_m=end,height_m=height+9 if not rtg else height+1.5,clearance_height_m=height-2,operating_envelope_xz_m=[-8,-6,end,6],pose="static")
    return a


def build():
    return [fishing("fishing_crane_post",7,12),fishing("fishing_crane_compact",5,8),fishing("fishing_crane_hydraulic",4,6,True),
            container("container_crane_feeder",24,22),container("container_crane_sts",36,38),container("container_crane_rtg",16,7,True)]
