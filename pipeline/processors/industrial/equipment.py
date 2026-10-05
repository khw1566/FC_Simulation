"""증류탑·대형 연통·액체 저장고·구형 LPG 저장고."""

from .geometry import IndustrialMesh


def build(kind):
    mesh=IndustrialMesh()
    if kind=='distillation_tower':
        mesh.box((0,.4,0),(14,.8,14),"deck")
        mesh.cylinder((0,.8,0),(0,39,0),3.2,"steel",24)
        mesh.sphere((0,39,0),3.2,rise=2,hemisphere=True)
        for y in (9,19,29,38): mesh.platform(4.4,y)
        mesh.ladder(0,4.0,39)
        for x in (-1.7,1.7):
            mesh.cylinder((x,1,5.3),(x,33,5.3),.24,"steel",10)
            for y in (8,18,28): mesh.cylinder((x,y,5.3),(x,y,2.8),.24,"steel",10)
        mesh.box((0,1.1,5.3),(5,2.2,1),"deck")
    elif kind=='industrial_chimney':
        mesh.box((0,.6,0),(15,1.2,15),"deck")
        mesh.tube((0,0),65,4.4,2.8)
        for y in (45,53,61):
            r=4.4+(2.8-4.4)*y/65
            mesh.chimney_band(y,1.5,r+.04,r+.04-1.6*1.5/65)
        mesh.platform(4.1,36)
        mesh.ladder(0,4.3,37)
    elif kind=='liquid_storage_tank':
        mesh.cylinder((0,0,0),(0,.7,0),17,"deck",32)
        mesh.cylinder((0,.7,0),(0,16.7,0),16,"white",32)
        mesh.sphere((0,16.7,0),16,rise=2,hemisphere=True)
        for y in (4.7,8.7,12.7): mesh.cylinder((0,y,0),(0,y+.12,0),16.06,"steel",32)
        mesh.ladder(0,16.1,17.5)
        mesh.cylinder((0,18.6,0),(0,19.8,0),.4,"steel",12)
        mesh.cylinder((16,1.7,0),(19,1.7,0),.4,"steel",12)
        mesh.box((18,1.1,0),(.6,2.2,.6),"deck")
    elif kind=='lpg_sphere':
        mesh.box((0,.3,0),(25,.6,25),"deck")
        for x in (-4.5,4.5):
            for z in (-4.5,4.5):
                mesh.box((x,.8,z),(2.6,1.6,2.6),"white")
                mesh.cylinder((x,1.6,z),(x,10,z),.45,"steel",10)
        mesh.sphere((0,13,0),9)
        mesh.ladder(0,9.2,14)
        mesh.cylinder((0,22,0),(0,23.4,0),.5,"steel",12)
        mesh.cylinder((0,4,0),(0,2.2,0),.3,"steel",10)
        mesh.cylinder((0,2.2,0),(10,2.2,0),.3,"steel",10)
    return mesh
