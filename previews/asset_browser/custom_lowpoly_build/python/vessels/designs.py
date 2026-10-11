"""여섯 선종의 실루엣과 갑판 장비 구성."""

from .mesh import VesselMesh

SPECS = {
    "container_ship": ("컨테이너선", 180, 28, 7, 5),
    "tugboat": ("예인선", 30, 10, 3, 2.2),
    "motor_boat": ("보트", 12, 3.8, .8, 1.1),
    "lpg_carrier": ("LPG선", 145, 24, 6, 4),
    "oil_tanker": ("유조선", 210, 34, 9, 5.5),
    "fishing_boat": ("어업용 소형선박", 18, 5.4, 1.5, 1.5),
}


def bridge(mesh, width, height, length, y, z):
    mesh.box((0,y+height/2,z),(width,height,length),"white")
    mesh.box((0,y+height*.72,z-length*.505),(width*.88,height*.22,.12),"glass")
    for side in (-1,1):
        mesh.box((side*width*.505,y+height*.72,z),( .12,height*.22,length*.82),"glass")
    mesh.box((0,y+height+.12,z),(width*1.08,.24,length*1.08),"white")


def railing(mesh, length, beam, y):
    radius = max(.035,beam*.004)
    for side in (-1,1):
        x = side*beam*.46
        for i in range(3):
            z = length*(-.20+i*.30)
            mesh.cylinder((x,y,z),(x,y+.9,z),radius,"white",6)
        mesh.cylinder((x,y+.9,-length*.20),(x,y+.9,length*.40),radius,"white",6)


def mast(mesh, x, y, z, height):
    mesh.cylinder((x,y,z),(x,y+height,z),max(.06,height*.025),"white",8)
    mesh.box((x,y+height*.8,z),(height*.65,.10,.15),"white")
    mesh.box((x,y+height,z),(.55,.12,.22),"dark")


def build_vessel(kind):
    _, length, beam, draft, deck = SPECS[kind]
    m = VesselMesh()
    m.hull(length,beam,draft,deck)
    if kind in ("container_ship","lpg_carrier","oil_tanker"):
        m.box((0,deck+3,length*.33),(beam*.66,6,length*.14),"white")
        bridge(m,beam*.72,4,length*.075,deck+6,length*.35)
        # 선미 배기 케이싱을 갑판에 닿게 하여 연통 하단을 지지한다.
        m.box((beam*.20,deck+4.25,length*.41),(beam*.20,8.5,length*.055),"white")
        m.box((beam*.20,deck+11,length*.41),(beam*.16,5,length*.045),"ochre")
        m.box((beam*.20,deck+13.6,length*.41),(beam*.18,.35,length*.05),"dark")
        mast(m,0,deck+10,length*.34,5)
        # 주황색 구조정 두 척.
        for side in (-1,1):
            m.box((side*beam*.38,deck+2.5,length*.29),(beam*.10,1.7,length*.04),"orange")
        railing(m,length,beam,deck)
        for z in (-length*.40,length*.43):
            for x in (-beam*.25,beam*.25):
                m.cylinder((x,deck,z),(x,deck+.6,z),.25,"dark",8)
    if kind == "container_ship":
        for row in range(8):
            for col in range(5):
                for level in range(3 if row in (0,7) else 4):
                    x = (col-2)*4.5
                    z = -length*.32+row*12.5
                    y = deck+1.35+level*2.7
                    color = ("red","blue","ochre","green")[(row+col+level)%4]
                    m.box((x,y,z),(4.25,2.55,12),color)
                    # 측면 수직 보강재로 적재 상자의 크기감을 표현한다.
                    if col in (0,4):
                        for offset in ():
                            m.box((x+(-2.15 if col==0 else 2.15),y,z+offset),
                                  (.08,2.4,.10),color)
    elif kind == "lpg_carrier":
        for z in (-length*.28,-length*.045,length*.19):
            for x in (-beam*.21,beam*.21):
                m.box((x,deck+.6,z),(beam*.36,1.2,length*.20),"dark")
                m.cylinder((x,deck+4.5,z-length*.09),
                           (x,deck+4.5,z+length*.09),3.8,"steel",16)
                m.cylinder((x,deck+8.0,z),(x,deck+9.0,z),.55,"red",10)
        m.cylinder((0,deck+1, -length*.38),(0,deck+1,length*.24),.25,"ochre")
        m.box((0,deck+1.8,0),(2,.25,length*.64),"white")
    elif kind == "oil_tanker":
        for x in (-beam*.13,0,beam*.13):
            m.cylinder((x,deck+.6,-length*.38),(x,deck+.6,length*.24),.35,"ochre",8)
        for z in [-length*.30+i*length*.085 for i in range(7)]:
            for x in (-beam*.29,beam*.29):
                m.cylinder((x,deck,z),(x,deck+.65,z),1.5,"steel",12)
                m.cylinder((x,deck+.7,z),(0,deck+.7,z),.18,"ochre",8)
        for x in (-beam*.34,beam*.34):
            mast(m,x,deck,length*.03,6)
        m.box((0,deck+1.65,-length*.04),(2,.3,length*.57),"white")
        m.cylinder((-4,deck+1,length*.18),(4,deck+1,length*.18),.5,"red")
    elif kind == "tugboat":
        bridge(m,6,4,6,deck,-2)
        bridge(m,5.5,2.4,4,deck+4,-2.3)
        for x in (-2.2,2.2):
            # 선교 뒤의 배기 케이싱은 갑판부터 연통 하단까지 연결한다.
            m.box((x,deck+2,2),(1.3,4,2),"white")
            m.cylinder((x,deck+4,2),(x,deck+8,2),.5,"ochre")
            m.cylinder((x,deck+8,2),(x,deck+8.4,2),.53,"dark")
        for side in (-1,1):
            m.cylinder((side*4.7,1.8,-7),(side*4.7,1.8,10),.55,"dark")
            for z in (-6,-2,2,6,10):
                m.cylinder((side*4.5,1.1,z),(side*5.1,1.1,z),.65,"dark")
        m.cylinder((-2,deck+.8,8),(2,deck+.8,8),.8,"steel")
        m.box((0,deck+.5,8),(5,1,3),"dark")
        m.cylinder((0,deck,5),(0,deck+1.6,5),.4,"ochre")
        mast(m,0,deck+6.5,-2,3)
        railing(m,length,beam,deck)
    elif kind == "motor_boat":
        m.box((0,deck+.18,0),(3.0,.36,7.0),"white")
        bridge(m,2.5,1.6,3,deck+.36,-.8)
        m.box((0,deck+.7,3),(2.8,1.1,1.8),"white")
        for x in (-.85,.85):
            m.box((x,.1,6),( .6,1.5,.8),"dark")
        mast(m,0,deck+2.2,-.7,1.0)
    elif kind == "fishing_boat":
        bridge(m,3.6,2.6,4.2,deck,-2.7)
        m.box((0,deck+.15,3.4),(3.7,.3,5.2),"green")
        for x in (-1.8,1.8):
            m.cylinder((x,deck,5),(x,deck+4.2,5),.10,"steel",8)
        m.cylinder((-1.8,deck+4.2,5),(1.8,deck+4.2,5),.13,"steel",8)
        m.cylinder((0,deck+.9,2),(0,deck+4.2,5),.08,"dark",6)
        m.cylinder((-1,deck+.7,4),(1,deck+.7,4),.65,"ochre",12)
        for z in (1.5,3):
            m.box((1.2,deck+.5,z),(.9,.8,1),"blue")
        for side in (-1,1):
            for z in (-4,0,4):
                m.cylinder((side*2.6,.8,z),(side*2.85,.8,z),.4,"dark",10)
        mast(m,0,deck+2.8,-3,2.3)
        railing(m,length,beam,deck)
    return m
