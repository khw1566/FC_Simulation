"""월성 1~4호기 외관을 참고한 비실측 게임용 모델."""

import math
from vessels.mesh import VesselMesh


def dome(mesh, x, z, radius=21, base=38, rise=12):
    segments, rings = 12, 3
    for row in range(rings):
        a, b = row * math.pi / (2*rings), (row+1) * math.pi / (2*rings)
        for col in range(segments):
            t, u = col*2*math.pi/segments, (col+1)*2*math.pi/segments
            def point(angle, phi):
                return (x+radius*math.cos(angle)*math.cos(phi),
                        base+rise*math.sin(angle),
                        z+radius*math.cos(angle)*math.sin(phi))
            mesh.quad(point(a,t), point(b,t), point(b,u), point(a,u), "white")


def build_complex():
    mesh = VesselMesh()
    mesh.box((0,-1.5,0),(330,3,720),"deck")
    # 독립 에셋의 로컬 배치이며 실제 지리 좌표나 설비 배치를 나타내지 않는다.
    for i, z in enumerate((-255,-85,85,255)):
        x = -65 if i == 0 else -50
        mesh.box((x,1,z),(54,2,54),"steel")
        mesh.cylinder((x,2,z),(x,38,z),21,"white",40)
        dome(mesh,x,z)
        mesh.cylinder((x,36.8,z),(x,38,z),21.5,"steel",40)
        mesh.box((x+47,12,z),(50,24,58),"white")
        mesh.box((73,15,z),(112,30,66),"white")
        mesh.box((73,30.6,z),(115,1.2,69),"blue")
        for offset in (-24,-12,0,12,24):
            mesh.box((73,33,z+offset),(98,4,3),"steel")
            mesh.box((73,20,z+offset),(110.4,3,2),"glass")
        mesh.box((-110,8,z+39),(36,16,32),"white")
        mesh.cylinder((-113,0,z+61),(-113,58,z+61),2.1,"steel",12)
        mesh.cylinder((-113,51,z+61),(-113,54,z+61),2.15,"red",12)
        for offset in (-18,0,18):
            mesh.box((140,3,z+offset),(12,6,10),"steel")
        # 도로와 지붕의 반복 형태로 원거리 판독성을 확보한다.
    mesh.box((-143,.12,0),(9,.24,690),"dark")
    mesh.box((24,.12,0),(10,.24,690),"dark")
    for z in (-340,0,340):
        mesh.box((0,.15,z),(300,.3,8),"dark")
    mesh.box((-100,6,-320),(55,12,25),"white")
    mesh.box((-100,10,-332.6),(48,2,.3),"glass")
    for z in range(-310,320,54):
        mesh.box((-161,1.7,z),(.35,3.4,.35),"steel")
        mesh.box((161,1.7,z),(.35,3.4,.35),"steel")
    for x in (-161,161):
        for y in (1,2.5):
            mesh.box((x,y,0),(.15,.15,665),"steel")
    return mesh
