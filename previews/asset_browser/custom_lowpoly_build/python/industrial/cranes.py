"""타워 크레인과 조선용 갠트리 크레인의 고정 포즈 메시."""

from .geometry import IndustrialMesh


def truss(mesh,a,b,width,material='ochre'):
    # X 방향 수평 사각 트러스.
    x0,y,z=a; x1,_,_=b
    for dy in (-width/2,width/2):
        for dz in (-width/2,width/2): mesh.beam((x0,y+dy,z+dz),(x1,y+dy,z+dz),.25,.25,material)
    count=max(1,int(abs(x1-x0)/12))
    for i in range(count):
        x=x0+(x1-x0)*i/count; end=x0+(x1-x0)*(i+1)/count
        for dz in (-width/2,width/2):
            mesh.beam((x,y-width/2,z+dz),(end,y+width/2,z+dz),.18,.18,material)
            mesh.beam((x,y+width/2,z+dz),(end,y-width/2,z+dz),.18,.18,material)


def build(kind):
    mesh=IndustrialMesh()
    if kind=='tower_crane':
        mesh.box((0,.5,0),(10,1,10),'deck')
        for y in range(1,53,4):
            for x in (-1.5,1.5):
                for z in (-1.5,1.5):
                    mesh.beam((x,y,z),(x,y+4,z),.28,.28,'ochre')
                    mesh.beam((x,y,z),(-x,y+4,z),.16,.16,'ochre')
                    mesh.beam((x,y,z),(x,y+4,-z),.16,.16,'ochre')
        truss(mesh,(-18,55,0),(60,55,0),2.5)
        mesh.box((-13,54,0),(8,3,4),'deck')
        mesh.box((2.5,53,2.1),(4,3,3),'glass')
        mesh.beam((0,55,0),(0,65,0),.4,.4,'ochre')
        for x in (-18,52): mesh.cylinder((0,65,0),(x,56,0),.08,'steel',6)
        mesh.box((35,53.5,0),(3,1,3),'dark')
        mesh.cylinder((35,53,0),(35,20,0),.08,'dark',6)
        mesh.box((35,19,0),(1.5,2,1),'ochre')
    elif kind=='gantry_crane':
        for x in (-42,42):
            mesh.box((x,1,0),(12,2,34),'dark')
            for z in (-12,12):
                mesh.beam((x,2,z),(x*.9,52,z*.3),2.2,2.2,'orange')
            mesh.beam((x,22,-8),(x,22,8),1.2,1.2,'orange')
        for z in (-4,4): truss(mesh,(-48,54,z),(48,54,z),4,'orange')
        mesh.box((10,53,0),(10,3,13),'steel')
        mesh.box((14,50,6),(4,4,4),'glass')
        for x in (7,13):
            for z in (-2,2): mesh.cylinder((x,51,z),(x,18,z),.10,'dark',6)
        mesh.box((10,18,0),(9,1.5,6),'ochre')
    else: raise ValueError(kind)
    return mesh
