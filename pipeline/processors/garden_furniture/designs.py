"""국가정원 배치용 범용 시설물: 근경과 원경의 형상과 원점을 맞춘다."""
import math
from .mesh import GardenMesh

SPECS = {
    'korean_pavilion': ('육각 목조 정자', 70, 650),
    'park_bench': ('등받이 벤치', 25, 150),
    'backless_bench': ('평벤치', 25, 150),
    'square_canopy': ('소형 천막', 50, 450),
    'festival_marquee': ('대형 행사 천막', 80, 800),
    'picnic_table': ('피크닉 테이블', 35, 250),
}


def ring(radius, height, count=6):
    return [(radius*math.cos(i*2*math.pi/count), height,
             radius*math.sin(i*2*math.pi/count)) for i in range(count)]


def roof(mesh, vertices, triangles, material='white'):
    for a,b,c in triangles:
        mesh.triangle(vertices[a],vertices[b],vertices[c],material)
        mesh.triangle(vertices[c],vertices[b],vertices[a],material)


def pavilion(mesh, far):
    for y,r,h in [(0.09,2.6,.18),(.24,2.4,.12)]:
        mesh.cylinder((0,y-h/2,0),(0,y+h/2,0),r,'deck',6)
    columns = ring(2.05,.3)
    for x,y,z in columns:
        if far:
            mesh.box((x,1.425,z),(.22,2.25,.22),'ochre')
        else:
            mesh.cylinder((x,y,z),(x,2.55,z),.12,'ochre',8)
    layers = [ring(2.9,2.58),ring(0,3.82)] if far else [
        ring(2.9,2.58),ring(2.45,2.63),ring(1.75,3.2),ring(.7,3.62),ring(0,3.82)]
    for row in range(len(layers)-1):
        for i in range(6):
            j=(i+1)%6
            # 지붕 위쪽 법선이 바깥을 향한다.
            mesh.quad(layers[row][i],layers[row+1][i],layers[row+1][j],layers[row][j],'hull')
    for i in range(6):
        mesh.triangle((0,2.58,0),layers[0][i],layers[0][(i+1)%6],'ochre')
    if not far:
        for i in range(6):
            a,b=columns[i],columns[(i+1)%6]
            mesh.cylinder((a[0],2.5,a[2]),(b[0],2.5,b[2]),.09,'ochre',6)
            mesh.cylinder(layers[0][i],layers[0][(i+1)%6],.065,'hull',6)
            if i not in [1,4]:
                for height in [.65,.95]:
                    mesh.cylinder((a[0],height,a[2]),(b[0],height,b[2]),.045,'ochre',4)


def bench(mesh, far, back=True):
    wood='ochre'
    if far:
        mesh.box((0,.45,0),(1.8,.08,.475),wood)
        for x in [-.65,.65]:
            mesh.box((x,.205,0),(.12,.41,.46),'dark')
        if back:
            mesh.box((0,.79,.22),(1.8,.605,.075),wood)
    else:
        for z in [-.2,-.1,0,.1,.2]:
            mesh.box((0,.45,z),(1.8,.08,.075),wood)
        for x in [-.65,.65]:
            for z in [-.17,.17]:
                mesh.box((x,.205,z),(.065,.41,.065),'dark')
            mesh.box((x,.375,0),(.08,.07,.47),'dark')
            if back:
                mesh.box((x,.755,.21),(.065,.61,.065),'dark')
                mesh.box((x,.61,0),(.055,.26,.055),'dark')
                mesh.box((x,.75,0),(.095,.05,.46),wood)
        if back:
            for y in [.59,.74,.89,1.04]:
                mesh.box((0,y,.22),(1.8,.105,.075),wood)


def canopy(mesh, far, large=False):
    width,length,eave,peak=(6,12,2.7,4.3) if large else (3,3,2.1,3.1)
    w,l=width/2,length/2
    positions=[(-w,-l),(w,-l),(-w,l),(w,l)]
    if large:
        positions += [(-w,0),(w,0)]
    for x,z in positions:
        mesh.box((x,eave/2,z),(.065,eave,.065),'steel')
    if large:
        verts=[(-w,eave,-l),(w,eave,-l),(w,eave,l),(-w,eave,l),
               (0,peak,-l),(0,peak,l)]
        tris=[(0,4,5),(0,5,3),(4,1,2),(4,2,5),(0,1,4),(3,5,2)]
    else:
        verts=[(-w,eave,-l),(w,eave,-l),(w,eave,l),(-w,eave,l),(0,peak,0)]
        tris=[(0,4,1),(1,4,2),(2,4,3),(3,4,0)]
    roof(mesh,verts,tris)
    for x in [-w,w]:
        mesh.box((x,eave-.1,0),(.035,.2,length),'white')
    for z in [-l,l]:
        mesh.box((0,eave-.1,z),(width,.2,.035),'white')
    if not far:
        for x,z in positions:
            mesh.box((x,.025,z),(.2,.05,.2),'dark')
        for z in [-l,l]:
            mesh.cylinder((-w,eave-.25,z),(w,eave-.02,z),.025,'steel',5)
            mesh.cylinder((-w,eave-.02,z),(w,eave-.25,z),.025,'steel',5)
    if large:
        for x in [-w,w]:
            mesh.box((x,1.2,0),(.025,2.3,length*.72),'white')
            if not far:
                for z in [-3,0,3]:
                    mesh.box((x+(-.02 if x<0 else .02),1.45,z),(.025,.65,1.35),'glass')


def picnic(mesh, far):
    if far:
        mesh.box((0,.76,0),(1.8,.09,.8),'ochre')
        for z in [-.65,.65]:
            mesh.box((0,.44,z),(1.8,.09,.29),'ochre')
        for x in [-.6,.6]:
            mesh.box((x,.345,0),(.12,.69,1.3),'dark')
    else:
        for z in [-.32,-.16,0,.16,.32]:
            mesh.box((0,.76,z),(1.8,.085,.135),'ochre')
        for side in [-1,1]:
            for z in [-.095,.095]:
                mesh.box((0,.44,side*.65+z),(1.8,.08,.13),'ochre')
        for x in [-.6,.6]:
            mesh.cylinder((x,.04,-.65),(x,.71,-.27),.065,'dark',6)
            mesh.cylinder((x,.04,.65),(x,.71,.27),.065,'dark',6)
            mesh.box((x,.37,0),(.085,.075,1.5),'dark')


def build(kind, far=False):
    mesh=GardenMesh()
    if kind=='korean_pavilion': pavilion(mesh,far)
    elif kind=='park_bench': bench(mesh,far,True)
    elif kind=='backless_bench': bench(mesh,far,False)
    elif kind=='square_canopy': canopy(mesh,far,False)
    elif kind=='festival_marquee': canopy(mesh,far,True)
    elif kind=='picnic_table': picnic(mesh,far)
    else: raise ValueError(kind)
    return mesh
