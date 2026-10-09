"""공통 보행 단면을 사용하는 데크·광장·분기·경사로·난간·지지대."""
import math
from road_assets.mesh import RoadMesh
from road_assets.profiles import WALK_HEIGHT, profile, port, route, route_ports
from road_assets.surfaces import sample, path_length
from road_assets.low_detail import coarse_route, surface_lines

STYLES={"wood_long":("종방향 목재","wood","wood_long"),
        "wood_cross":("횡방향 목재","wood","wood_cross"),
        "weathered":("풍화 목재","wood_weathered","wood_cross"),
        "stone":("석판 데크","stone","large_slabs")}


def frame(mesh, points, width):
    # 바닥 하부 보강은 보행 표면과 분리된 높이에 둔다.
    for offset in (-width*.35,width*.35):
        mesh.strip(points,offset-.06,offset+.06,-.04,"steel",-.20)
    length=path_length(points)
    for i in range(2):
        p=sample(points,length*(i+.5)/2)
        a=mesh.at(p,-width/2,-.10); b=mesh.at(p,width/2,-.10)
        mesh.beam(a,b,.10,.10,"steel")


def surface(style,width,shape):
    label,material,mode=STYLES[style]; mesh=RoadMesh(); points=coarse_route(shape,width)
    mesh.strip(points,-width/2,width/2,.15,material,.075)
    surface_lines(mesh,points,width,.15,material,mode)
    frame(mesh,points,width)
    # 접속 높이는 기존 보행로와 같은 0.15m다.
    ports=route_ports(points,profile("walk",width,0,WALK_HEIGHT))
    return mesh,ports


def platform(style,size,shape="plaza"):
    mesh=RoadMesh(); material,mode=STYLES[style][1:]
    ports=[]; h=WALK_HEIGHT; cross=profile("walk",3,0,h)
    if shape=="plaza":
        blocks=[(0,0,size,size)]; edge=size/2
    else:
        blocks=[(0,0,3,3),(0,-4.5,3,6),(0,4.5,3,6),(4.5,0,6,3)]
        if shape=="cross": blocks.append((-4.5,0,6,3))
        edge=7.5
    for x,z,w,d in blocks:
        points=[(x,z-d/2,0),(x,z+d/2,0)]
        mesh.strip(points,-w/2,w/2,.15,material,.075)
        surface_lines(mesh,points,w,.15,material,mode); frame(mesh,points,w)
    for name,(dx,dz) in {"North":(0,-1),"South":(0,1),"East":(1,0),"West":(-1,0)}.items():
        if shape=="tee" and name=="West": continue
        ports.append(port(name,(dx*edge,h,dz*edge),(dx,0,dz),cross))
    return mesh,ports


def ramp(width):
    mesh=RoadMesh(); vertices=[]
    for z,top in ((-6,.15),(6,1.15)):
        vertices.extend([(-width/2,top-.10,z),(width/2,top-.10,z),
                         (width/2,top,z),(-width/2,top,z)])
    for indexes in ((0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)):
        mesh.quad(*(vertices[i] for i in indexes),"wood")
    for x in (-width*.35,width*.35): mesh.beam((x,-.05,-6),(x,.95,6),.12,.12,"steel")
    # 경사면은 단색 판으로 유지한다.
    ports=[port("Start",(0,.15,-6),(0,0,-1),profile("walk",width,0,.15)),
           port("End",(0,1.15,6),(0,0,1),profile("walk",width,0,1.15))]
    return mesh,ports


def railing(style,length=6):
    mesh=RoadMesh(); mat="wood" if style=="wood" else "steel"
    for z in (-length/2,0,length/2): mesh.box((0,.55,z),(.08,1.1,.08),mat)
    for height in (.45,1.1): mesh.box((0,height,0),(.07,.07,length),mat)
    if style=="wood":
        # 판재 세부 대신 중앙 기둥과 두 가로대만 사용한다.
        pass
    return mesh


def curved_railing(style,shape,side):
    mesh=RoadMesh(); points=coarse_route(shape,3); offset=side*1.44
    mat="wood" if style=="wood" else "steel"; length=path_length(points)
    for i in range(3):
        p=sample(points,length*i/2)
        a=mesh.at(p,offset,0); b=mesh.at(p,offset,1.1)
        mesh.beam(a,b,.075,.075,mat)
    heights=(.45,1.1)
    for a,b in zip(points,points[1:]):
        for y in heights:
            mesh.beam(mesh.at(a,offset,y),mesh.at(b,offset,y),.025 if style=="cable" and y<1 else .06,.05,mat)
    return mesh


def sloped_railing(style):
    mesh=RoadMesh(); mat="wood" if style=="wood" else "steel"
    for z in (-6,0,6):
        rise=(z+6)/12
        mesh.box((0,rise+.55,z),(.08,1.1,.08),mat)
    for y in (.45,1.1):
        mesh.beam((0,y,-6),(0,y+1,6),.025 if style=="cable" and y<1 else .06,.06,mat)
    return mesh


def support(width,height):
    mesh=RoadMesh()
    for x in (-width*.35,width*.35):
        mesh.box((x,-height/2,0),(.18,height,.18),"steel")
    mesh.box((0,-.07,0),(width,.14,.20),"steel")
    return mesh


def models():
    for style,(label,_,_) in STYLES.items():
        for width in (1.5,3,4.5):
            mesh,ports=surface(style,width,"straight")
            yield f"deck_{style}_w{width:g}_straight",f"{label} / 폭 {width:g}m 데크",mesh,ports,{
                "kind":"deck_surface","style":style,"width":width,"length_m":12,"shape":"straight",
                "support_mount_y_m":-.20,"railing_mount_y_m":.15,"rails_included":False}
        for shape in ("curve45","curve90"):
            mesh,ports=surface(style,3,shape)
            yield f"deck_{style}_w3_{shape}",f"{label} / {45 if shape=='curve45' else 90}도 데크",mesh,ports,{
                "kind":"deck_surface","style":style,"width":3,"shape":shape,"support_mount_y_m":-.20,
                "rails_included":False,"curved_rail_required":True}
        for size in (6,12):
            mesh,ports=platform(style,size)
            yield f"deck_{style}_plaza_{size}m",f"{label} / {size}m 광장",mesh,ports,{
                "kind":"deck_platform","style":style,"platform_size_m":size,"opening_width_m":3,"shape":"plaza",
                "support_mount_y_m":-.20,"rails_included":False,"unconnected_edges_need_closure":True}
        for shape in ("tee","cross"):
            mesh,ports=platform(style,3,shape)
            yield f"deck_{style}_w3_{shape}",f"{label} / {'T자' if shape=='tee' else '십자'} 분기",mesh,ports,{
                "kind":"deck_platform","style":style,"width":3,"shape":shape,"support_mount_y_m":-.20,"rails_included":False}
    for width in (1.5,3,4.5):
        mesh,ports=ramp(width)
        yield f"deck_ramp_w{width:g}_rise1m",f"폭 {width:g}m / 높이 1m 전환 데크",mesh,ports,{
            "kind":"deck_ramp","width":width,"rise_m":1,"run_m":12,"slope":1/12,
            "rails_included":False,"sloped_rail_required":True,"accessibility_certified":False}
    for style,label in (("wood","목재"),("steel","강철"),("cable","케이블")):
        yield f"deck_rail_{style}_6m",f"{label} / 6m 데크 난간",railing(style),[],{
            "kind":"deck_railing","style":style,"length_m":6,"placement_y_m":.15,"railing_height_m":1.1,
            "attachment_role":"edge","straight_only":True}
    for style,label in (("wood","목재"),("steel","강철"),("cable","케이블")):
        for length in (1.5,3):
            yield f"deck_rail_{style}_{length:g}m",f"{label} / {length:g}m 마감 난간",railing(style,length),[],{
                "kind":"deck_railing","style":style,"length_m":length,"placement_y_m":.15,"railing_height_m":1.1,
                "attachment_role":"plaza_edge_closure","straight_only":True}
    for style,label in (("wood","목재"),("steel","강철"),("cable","케이블")):
        for shape in ("curve45","curve90"):
            for side in (-1,1):
                side_name="left" if side<0 else "right"
                yield f"deck_rail_{style}_w3_{shape}_{side_name}",f"{label} / 곡선 {side_name} 난간",curved_railing(style,shape,side),[],{
                    "kind":"deck_railing","style":style,"shape":shape,"width":3,"side":side_name,
                    "attach_position_m":[0,.15,0],"same_origin_as_surface":True,"railing_height_m":1.1}
        yield f"deck_rail_{style}_rise1m",f"{label} / 경사 데크 난간",sloped_railing(style),[],{
            "kind":"deck_railing","style":style,"shape":"ramp","rise_m":1,"run_m":12,
            "attach_y_m":.15,"attach_x_formula":"side * (deck_width / 2 - 0.06)"}
    for width in (3,4.5):
        for height in (1.5,3,6):
            yield f"deck_support_w{width:g}_h{height:g}",f"폭 {width:g}m / 높이 {height:g}m 지지대",support(width,height),[],{
                "kind":"deck_support","width":width,"height_m":height,"mount_y_m":0,
                "attachment_role":"underframe","mount_position_on_deck_m":[0,-.20,0]}
