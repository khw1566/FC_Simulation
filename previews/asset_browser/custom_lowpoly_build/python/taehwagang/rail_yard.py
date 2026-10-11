"""정적 승강장, 캐노피, 선로 및 전차선 구역."""

from .geometry import StationMesh


def build(config):
    mesh = StationMesh()
    length = config["platform_length_m"]
    center = -155
    mesh.box((0,.02,-156),(105,.04,268),"deck")
    for x in config["track_centers_x_m"]:
        mesh.box((x,.10,center),(3.5,.2,length+25),"deck")
        for z in range(-279,-31,8):
            mesh.box((x,.25,z),(2.6,.18,.28),"steel")
        for dx in (-.7175,.7175):
            mesh.box((x+dx,.43,center),(.075,.18,length+25),"steel")
        for z in range(-269,-39,35):
            mesh.cylinder((x+3.2,0,z),(x+3.2,8,z),.12,"steel",6)
            mesh.beam((x+3.2,8,z),(x,7.4,z),.1,.1,"steel")
        mesh.cylinder((x,7.4,-278),(x,7.4,-32),.025,"dark",6)
    for x in config["platform_centers_x_m"]:
        mesh.box((x,.9,center),(9,1.8,length),"white")
        for dx in (-4.1,4.1):
            mesh.box((x+dx,1.82,center),(.45,.04,length-4),"ochre")
        mesh.box((x,6.3,center),(10,.3,length-28),"steel")
        for z in range(-250,-49,20):
            mesh.box((x,4.0,z),(.25,4.4,.25),"steel")
            mesh.box((x,5.9,z),(9,.22,.22),"steel")
            mesh.box((x,2.35,z+3),(3,.2,.65),"dark")
            mesh.box((x,4.8,z+4),(2.8,.7,.16),"blue")
        # 통로 하단 5.5m에서 승강장 1.8m로 이어지는 계단.
        for i in range(19):
            top = 1.8+(i+1)*3.7/19
            mesh.box((x,(1.8+top)/2,-52+i*.65),(3.2,top-1.8,.65),"white")
        mesh.box((x,3.65,-32),(3.2,3.7,3.4),"glass")
    for x in (-55,55):
        for z in range(-278,-28,36):
            mesh.box((x,1.2,z),(.12,2.4,.12),"steel")
        for y in (.6,1.7):
            mesh.box((x,y,-155),(.06,.06,250),"steel")
    return mesh
