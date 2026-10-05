"""연결점이 있는 고가 배관 직선·곡관·분기 모듈."""

import math
from .geometry import IndustrialMesh

CONNECTORS={
    'pipeline_straight':[[-12,5,0],[12,5,0]],
    'pipeline_elbow':[[-12,5,0],[0,5,12]],
    'pipeline_tee':[[-12,5,0],[12,5,0],[0,5,12]],
}
CONNECTOR_DIRECTIONS={
    'pipeline_straight':[[-1,0,0],[1,0,0]],
    'pipeline_elbow':[[-1,0,0],[0,0,1]],
    'pipeline_tee':[[-1,0,0],[1,0,0],[0,0,1]],
}


def build(kind):
    mesh=IndustrialMesh()
    for z in (-1.1,0,1.1):
        if kind=='pipeline_elbow':
            radius=4-z
            mesh.cylinder((-12,5,z),(-4,5,z),.32,"steel",12)
            points=[(-4+radius*math.sin(i*math.pi/16),5,4-radius*math.cos(i*math.pi/16)) for i in range(9)]
            for a,b in zip(points,points[1:]): mesh.cylinder(a,b,.32,"steel",12)
            mesh.cylinder((points[-1][0],5,4),(points[-1][0],5,12),.32,"steel",12)
        else:
            mesh.cylinder((-12,5,z),(12,5,z),.32,"steel",12)
            if kind=='pipeline_tee':
                mesh.cylinder((z,5,0),(z,5,12),.32,"steel",12)
    supports=[(-9,0),(9,0)] if kind=='pipeline_straight' else [(-9,0),(0,9)]
    if kind=='pipeline_tee': supports.append((9,0))
    for x,z in supports:
        branch=x==0 and z!=0
        mesh.box((x,.3,z),(5,.6,3) if branch else (3,.6,5),"deck")
        for offset in (-1.8,1.8):
            mesh.box((x+offset if branch else x,2.7,z if branch else z+offset),(.24,4.8,.24),"steel")
        mesh.box((x,4.6,z),(4.2,.3,.4) if branch else (.4,.3,4.2),"steel")
    return mesh
