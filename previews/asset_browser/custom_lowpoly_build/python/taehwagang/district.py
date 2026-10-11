"""주변 도로와 비실측 상업·주거 블록."""

from .geometry import StationMesh


def building(mesh,x,z,width,depth,floors):
    height = floors*3.4
    mesh.box((x,height/2,z),(width,height,depth),"white")
    mesh.box((x,height+.3,z),(width+1,.6,depth+1),"steel")
    for side in (-1,1):
        for floor in range(floors):
            mesh.box((x,2+floor*3.4,z+side*(depth/2+.06)),
                     (width-3,1.7,.12),"glass")
        for dx in range(-int(width/2)+3,int(width/2),5):
            mesh.box((x+dx,height/2,z+side*(depth/2+.15)),(.22,height,.22),"white")
    mesh.box((x,height+1,z),(width*.35,1.4,depth*.24),"deck")
    mesh.box((x,2,z-depth/2-.3),(width*.75,.8,.25),"dark")


def build(config):
    mesh = StationMesh()
    width, depth = config["district_size_m"]
    mesh.box((0,-1,0),(width,2,depth),"deck")
    mesh.box((0,.15,195),(width-8,.3,28),"dark")
    for z in (178,212):
        mesh.box((0,.23,z),(width-8,.46,6),"white")
    for z in (191,199):
        for x in range(-225,231,12):
            mesh.box((x,.32,z),(6,.04,.16),"white")
    mesh.box((0,.32,195),(width-12,.04,.24),"ochre")
    for x in (-206,-174,174,206):
        mesh.box((x,.32,195),(2,.04,27),"white")
    for x in range(-210,220,35):
        mesh.tree(x,214,.8)
        mesh.lamp(x,177)
    for i,x in enumerate((-196,-142,-88,-34,34,88,142,196)):
        building(mesh,x,252,36,40,3+i%4)
    # 선로 양쪽의 보조 건물 및 완충 녹지.
    for side in (-1,1):
        for i,z in enumerate((-210,-145,-80)):
            building(mesh,side*135,z,40,35,2+i)
            mesh.tree(side*91,z,1)
        mesh.box((side*192,.12,-142),(12,.24,268),"dark")
    return mesh
