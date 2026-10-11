"""공단 스카이라인을 구성하는 범용 연통·공정 탑 6종."""

from industrial.geometry import IndustrialMesh

SPECS = {
    'stack_concrete': ('고층 표식 연통', [(0,90,0)], 'smoke_gray'),
    'stack_steel': ('슬림 강철 연통', [(0,55,0)], 'smoke_gray'),
    'stack_triple': ('3구 집합 연통', [(-4,62,0),(0,62,0),(4,62,0)], 'smoke_gray'),
    'flare_lattice': ('격자 지지 플레어 탑', [(0,72,0)], None),
    'process_column': ('다단 정유 공정 탑', [], None),
    'scrubber_tower': ('습식 세정·배기 탑', [(0,38,0)], 'steam_white'),
}


def inlet(mesh):
    for z in (-1.1,0,1.1):
        mesh.cylinder((-12,5,z),(-6,5,z),.32,'steel',12)
    mesh.cylinder((-6,5,-1.6),(-6,5,1.6),.6,'steel',16)
    mesh.cylinder((-6,5,0),(0,5,0),.65,'steel',16)
    for z in (-1.8,1.8): mesh.box((-9,2.4,z),(.25,4.8,.25),'steel')
    mesh.box((-9,4.55,0),(.4,.3,4.2),'steel')


def build(kind):
    mesh=IndustrialMesh()
    mesh.box((0,.4,0),(16,.8,16),'deck')
    if kind=='stack_concrete':
        mesh.tube((0,0),90,5.1,2.6)
        for y in (62,70,78,86):
            r=5.1-2.5*y/90
            mesh.chimney_band(y,2,r+.025,r+.025-2.5*2/90)
        mesh.platform(5.2,42); mesh.ladder(0,5.4,43)
    elif kind=='stack_steel':
        mesh.tube((0,0),55,2.4,1.6)
        for y in (18,35,50): mesh.platform(3.1,y)
        mesh.ladder(0,3.2,51)
        for x in (-4,4): mesh.beam((x,0,0),(0,14,0),.35,.35,'steel')
    elif kind=='stack_triple':
        for x in (-4,0,4): mesh.tube((x,0),62,1.7,1.25)
        for y in (12,28,44,58):
            mesh.box((0,y,0),(13,.3,4.5),'steel')
            for z in (-2.2,2.2): mesh.box((0,y+1,z),(13,.12,.12),'steel')
        for x in (-6,6):
            for z in (-2,2): mesh.box((x,30,z),(.35,60,.35),'steel')
        mesh.ladder(-6,2.3,59)
    elif kind=='flare_lattice':
        mesh.tube((0,0),72,1.2,.75)
        for y in range(0,66,6):
            r=5-y*.045; top=r-.27
            for x in (-1,1):
                for z in (-1,1):
                    mesh.beam((x*r,y,z*r),(x*top,y+6,z*top),.24,.24,'steel')
                    mesh.beam((x*r,y,z*r),(-x*top,y+6,z*top),.16,.16,'steel')
                    mesh.beam((x*r,y,z*r),(x*top,y+6,-z*top),.16,.16,'steel')
        mesh.platform(2,66)
    elif kind=='process_column':
        mesh.cylinder((0,.8,0),(0,49,0),3.4,'steel',24)
        mesh.sphere((0,49,0),3.4,rise=2,hemisphere=True)
        for y in (8,17,26,35,44): mesh.platform(4.6,y)
        mesh.ladder(0,4.8,45)
        for z in (-5.6,5.6):
            mesh.cylinder((0,3,z),(0,43,z),.35,'steel',12)
            for y in (9,27,42): mesh.cylinder((0,y,z),(0,y,3 if z>0 else -3),.35,'steel',12)
    elif kind=='scrubber_tower':
        mesh.cylinder((0,.8,0),(0,25,0),4.2,'white',24)
        mesh.sphere((0,25,0),4.2,rise=2,hemisphere=True)
        mesh.tube((0,0),38,1.4,1.4)
        for y in (8,17,25): mesh.platform(5,y)
        mesh.ladder(0,5.2,26)
        mesh.box((5,3,0),(3,6,5),'deck')
        mesh.cylinder((4,7,0),(6,7,0),.7,'steel',16)
    else: raise ValueError(kind)
    inlet(mesh)
    return mesh
