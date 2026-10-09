"""부두 상판·벽·지지대·높이 전환. 기초는 지형에 따라 독립 선택한다."""
from .asset import HarborAsset


def deck(width,edge=False):
    key=f"quay_{width}x12"+("_sea_edge" if edge else "")
    a=HarborAsset(key,f"부두 상판 {width}×12m"+(" 해측 가장자리" if edge else ""),"quay")
    a.mesh.box((0,-.3,0),(width,.6,12),"concrete")
    a.ends(12,width)
    for name,x,d in (("Land",-width/2,-1),("Sea",width/2,1)):
        a.marker(name,(x,0,0),"quay_walk",(d,0,0),12)
    if edge:
        a.mesh.box((width/2-.2,-.8,0),(.4,1,12),"concrete_dark")
        a.marker("FenderMount",(width/2,-.8,0),"quay_edge",(1,0,0))
        for z in (-4,4): a.mesh.box((width/2-.25,.015,z),(.5,.03,1.5),"yellow")
    a.box_collision((0,-.3,0),(width,.6,12))
    a.extra.update(width_m=width,length_m=12,finished_surface_y_m=0,foundation_separate=True,sea_edge_side="+X" if edge else None)
    return a


def seawall(depth):
    a=HarborAsset(f"seawall_12m_depth{depth}m",f"호안 벽체 12m · 깊이 {depth}m","foundation")
    a.mesh.box((0,-depth/2,0),(1,depth,12),"concrete_dark")
    a.mesh.box((0,-.15,0),(1.3,.3,12),"concrete")
    a.ends(12,1,"seawall_1m"); a.box_collision((0,-depth/2,0),(1,depth,12))
    a.extra.update(foundation_depth_m=depth,embed_in_terrain_m=.25,terrain_policy="vertical_embed_keep_deck_level")
    return a


def footing(depth):
    a=HarborAsset(f"quay_foundation_{depth}m",f"부두 매립 기초 · 깊이 {depth}m","foundation")
    a.mesh.box((0,-.6-depth/2,0),(6,depth,12),"concrete_dark")
    a.box_collision((0,-.6-depth/2,0),(6,depth,12))
    a.marker("DeckUnderside",(0,-.6,0),"quay_foundation")
    a.extra.update(foundation_depth_m=depth,foundation_top_y_m=-.6,embed_in_terrain_m=.25,terrain_policy="vertical_embed_keep_deck_level")
    return a


def pile(depth):
    a=HarborAsset(f"pier_pile_{depth}m",f"부두 지지말뚝 · 높이 {depth}m","foundation")
    a.mesh.cylinder((0,-depth-.6,0),(0,-.6,0),.5,"concrete_dark",8)
    a.mesh.box((0,-.8,0),(1.6,.4,1.6),"concrete")
    a.marker("DeckUnderside",(0,-.6,0),"pile_cap")
    a.box_collision((0,-.6-depth/2,0),(1,depth,1))
    a.extra.update(foundation_depth_m=depth,foundation_top_y_m=-.6,terrain_policy="sample_support_point_keep_vertical")
    return a


def slope(key,label,width,length,start,end,end_width=None,profile="quay_walk",end_profile=None):
    end_width=width if end_width is None else end_width
    a=HarborAsset(key,label,"ramp")
    upper=[(-width/2,start,-length/2),(-end_width/2,end,length/2),(end_width/2,end,length/2),(width/2,start,-length/2)]
    lower=[(x,y-.45,z) for x,y,z in upper]
    a.mesh.quad(*upper,"concrete"); a.mesh.quad(*reversed(lower),"concrete_dark")
    for i in range(4):
        j=(i+1)%4; a.mesh.quad(lower[i],lower[j],upper[j],upper[i],"concrete_dark")
    a.convex_collision(upper+lower)
    a.marker("Start",(0,start,-length/2),profile,(0,0,-1),width)
    a.marker("End",(0,end,length/2),end_profile or profile,(0,0,1),end_width)
    a.extra.update(length_m=length,start_surface_y_m=start,end_surface_y_m=end,grade=(end-start)/length,foundation_separate=True)
    return a


def build():
    return [deck(w,edge) for w in (6,12) for edge in (False,True)]+[seawall(n) for n in (2,4,8)]+[footing(n) for n in (1,2,4,8)]+[pile(n) for n in (4,8,12)]+[
        slope(f"quay_ramp_rise{n}m",f"부두 경사로 +{n}m",6,12,0,n) for n in (1,2)]+[
        slope(f"slipway_drop{n}m",f"어선 진수 경사로 -{n}m",4,12,0,-n,profile="slipway_4m") for n in (2,4)]+[
        slope("quay_width_6to12","부두 폭 전환 6→12m",6,6,0,0,12),
        slope("breakwater_quay_adapter","방파제 4m→부두 6m 전환",4,6,0,0,6,"breakwater_4m","quay_walk"),
        slope("quay_walk_adapter_3m","부두→기존 보행로 3m 접속",6,6,0,.15,3,"quay_walk","walk")]
