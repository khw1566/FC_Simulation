"""역전광장, 정원, 버스·택시 승하차 구역과 주차장."""

from .geometry import StationMesh


def build(config):
    mesh = StationMesh()
    mesh.box((0,.02,99),(280,.04,154),"steel")
    mesh.box((0,.04,84),(215,.08,104),"white")
    for x in range(-96,97,12):
        mesh.box((x,.09,84),(.14,.04,100),"steel")
    for z in range(36,135,12):
        mesh.box((0,.09,z),(210,.04,.14),"steel")
    mesh.box((0,.16,77),(5,.16,105),"ochre")
    for x in (-73,73):
        for z in (51,87,121):
            mesh.box((x,.25,z),(25,.5,18),"steel")
            mesh.box((x,.55,z),(23,.1,16),"green")
            mesh.tree(x,z,.8)
            for side in (-1,1):
                mesh.box((x+side*14,.5,z),(1,1,7),"white")
    for x in (-108,108):
        for z in (40,70,105,134):
            mesh.lamp(x,z)
    # 버스·택시 구역은 정적 정류 시설이며 운행 시스템과 독립이다.
    mesh.box((0,.13,155),(276,.26,23),"dark")
    mesh.box((0,.32,144),(250,.64,2.2),"white")
    for x in (-96,-48,48,96):
        mesh.shelter(x,137,27,4.5)
        mesh.box((x,1.7,141),(.22,3.4,.22),"steel")
        mesh.box((x,3.1,141),(2,.6,.18),"blue")
    for x in range(-125,126,10):
        mesh.box((x,.29,155),(5,.04,.18),"white")
    for x in (-28,-22,-16,-10,-4,2,8,14,20,26):
        mesh.box((x,.29,155),(2,.04,20),"white")
    for x in (-140,140):
        mesh.box((x,.12,109),(14,.24,93),"dark")
    # 주차장: 제작용 54면, 실제 면수와 일치한다고 주장하지 않는다.
    mesh.box((187,.12,91),(84,.24,126),"dark")
    for z in (43,78,113):
        for i in range(19):
            x = 150+i*4.1
            mesh.box((x,.27,z),(.12,.04,11),"white")
        mesh.box((187,.27,z+5.5),(74,.04,.12),"white")
    # 자전거 거치 공간과 소형 타워를 제작용 형태로 표현한다.
    mesh.cylinder((-119,0,42),(-119,10,42),4,"steel",16)
    mesh.cylinder((-119,9,42),(-119,10.3,42),4.4,"dark",16)
    for i in range(12):
        x = -132+i*1.5
        mesh.beam((x,.05,57),(x,1,57),.05,.05,"steel")
        mesh.beam((x,1,57),(x,1,58.4),.05,.05,"steel")
        mesh.beam((x,1,58.4),(x,.05,58.4),.05,.05,"steel")
    return mesh
