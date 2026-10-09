"""계류·충격 완충·하역·어시장·설비와 레일 등 작은 항구 기반시설."""
from .asset import HarborAsset


def bollard():
    a=HarborAsset("mooring_bollard","계류 볼라드","mooring")
    a.mesh.box((0,.1,0),(1.1,.2,.9),"concrete_dark")
    a.mesh.cylinder((0,.2,0),(0,.8,0),.22,"steel",6)
    a.mesh.cylinder((-.45,.68,0),(.45,.68,0),.18,"steel",6)
    a.marker("MooringPoint",(0,.8,0),"mooring_line"); a.box_collision((0,.45,0),(1,.9,.7))
    return a


def fender(tire=False):
    a=HarborAsset("fender_tire" if tire else "fender_block","타이어형 부두 완충재" if tire else "사각 부두 완충재","fender")
    if tire:
        a.mesh.cylinder((-.18,0,0),(.18,0,0),.65,"dark",8)
        a.mesh.cylinder((.18,0,0),(.2,0,0),.3,"steel",8)
    else: a.mesh.box((0,0,0),(.45,1.5,1),"dark")
    a.marker("WallMount",(-.23,0,0),"quay_edge",(-1,0,0))
    a.extra.update(anchor="wall_mount",terrain_policy="use_quay_side_socket",visual_ring_simplified=True)
    return a


def ladder():
    a=HarborAsset("quay_ladder_3m","부두 사다리 3m","access")
    for z in (-.3,.3): a.mesh.beam((0,.5,z),(0,-3,z),.06,.06,"steel")
    for i in range(7): a.mesh.beam((0,-i*.45,-.3),(0,-i*.45,.3),.06,.06,"steel")
    a.marker("WallMount",(-.15,0,0),"quay_edge",(-1,0,0)); a.extra["climbable_runtime_behavior"]=False
    return a


def stairs():
    a=HarborAsset("quay_stairs_2m","부두 접근 계단 2m","access")
    for i in range(8):
        top=2*(i+1)/8; z=-2+(i+.5)*.5
        a.mesh.box((0,top/2,z),(3,top,.5),"concrete"); a.box_collision((0,top/2,z),(3,top,.5))
    a.marker("Start",(0,0,-2),"walk",(0,0,-1),3)
    a.marker("End",(0,2,2),"walk",(0,0,1),3)
    return a


def rail():
    a=HarborAsset("crane_rails_12m","컨테이너 크레인 레일 12m","crane_rail")
    for x in (-4,4): a.mesh.box((x,.07,0),(.12,.14,12),"steel")
    a.ends(12,8,"crane_rail_8m"); a.extra.update(rail_gauge_m=8,rail_top_y_m=.14)
    return a


def fence():
    a=HarborAsset("quay_guardrail_6m","부두 간단 난간 6m","accessory")
    for z in (-3,0,3): a.mesh.box((0,.55,z),(.08,1.1,.08),"steel")
    for y in (.55,1.1): a.mesh.box((0,y,0),(.07,.07,6),"steel")
    a.ends(6,.08,"guardrail"); a.box_collision((0,.55,0),(.1,1.1,6))
    return a


def building(key,label,width,depth,height,auction=False):
    a=HarborAsset(key,label,"building")
    a.mesh.box((0,.15,0),(width+.4,.3,depth+.4),"concrete_dark")
    a.mesh.box((0,height/2+.3,0),(width,height,depth),"white")
    a.mesh.profile([(-width/2-.4,height+.3),(width/2+.4,height+.3),(0,height+2)],depth/2+.4,-depth/2-.4,"blue")
    for x in (-width*.23,width*.23):
        a.mesh.box((x,1.6,depth/2+.04),(width*.28,2.6,.08),"dark")
    if auction:
        a.mesh.box((0,2.9,depth/2+2),(width,.25,4),"steel")
        for x in (-width*.43,width*.43): a.mesh.box((x,1.4,depth/2+3.4),(.15,2.8,.15),"steel")
    a.marker("Entrance",(0,0,depth/2+.3),"facility_access",(0,0,1),3)
    a.box_collision((0,height/2+.3,0),(width,height,depth))
    return a


def pedestal():
    a=HarborAsset("shore_power_water","선박 육상 전원·급수 설비","utility")
    a.mesh.box((0,.06,0),(1,.12,1),"concrete")
    a.mesh.box((0,.75,0),(.7,1.5,.6),"white")
    a.mesh.box((0,1.2,.31),(.45,.3,.02),"blue")
    a.mesh.cylinder((.35,.5,0),(.55,.5,0),.06,"steel",6)
    a.marker("UtilityOutlet",(.55,.5,0),"utility_socket",(1,0,0)); a.box_collision((0,.75,0),(.7,1.5,.6))
    return a


def lamp():
    a=HarborAsset("harbor_lamp_6m","항구 조명 기둥 6m","utility")
    a.mesh.cylinder((0,0,0),(0,6,0),.09,"steel",6)
    a.mesh.box((.5,6,0),(1.4,.15,.5),"steel")
    a.mesh.box((.75,5.9,0),(.55,.04,.4),"lens_warm")
    a.marker("LightSocket",(.75,5.8,0),"utility_light"); a.extra["light_node_default_enabled"]=False
    return a


def winch():
    a=HarborAsset("fishing_winch","소형 어선 인양 윈치","utility")
    a.mesh.box((0,.1,0),(1.8,.2,1.4),"concrete_dark")
    for x in (-.65,.65): a.mesh.box((x,.55,0),(.18,.9,1),"steel")
    a.mesh.cylinder((-.65,.6,0),(.65,.6,0),.42,"ochre",8)
    a.mesh.box((.95,.4,0),(.55,.7,.75),"steel")
    a.marker("CableExit",(0,.5,-.5),"hoist_attachment"); a.box_collision((0,.5,0),(2.2,1,1.4))
    return a


def build():
    return [bollard(),fender(),fender(True),ladder(),stairs(),rail(),fence(),
        building("fishing_shed","소형 어업 창고",6,9,3.2),building("harbor_warehouse","항구 하역 창고",12,18,5),
        building("fish_auction","소형 어시장 경매장",12,12,4,True),building("ice_storage","어업 얼음 저장고",6,6,3),
        pedestal(),lamp(),winch()]
