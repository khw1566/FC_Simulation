"""역사와 주변 시설의 공통 저다각형 기하 생성."""

import math
from vessels.mesh import VesselMesh


class StationMesh(VesselMesh):
    """기존 GLB 작성기를 재사용하고 건축 부재 생성만 확장한다."""

    def profile(self, points, front, back, material):
        # XY의 반시계 방향 볼록 단면을 Z 방향으로 압출한다.
        a = [(x, y, front) for x, y in points]
        b = [(x, y, back) for x, y in points]
        for i in range(1, len(points)-1):
            self.triangle(a[0], a[i], a[i+1], material)
            self.triangle(b[0], b[i+1], b[i], material)
        for i in range(len(points)):
            j = (i+1) % len(points)
            self.quad(a[i], b[i], b[j], a[j], material)

    def beam(self, a, b, width, depth, material):
        direction = [b[i]-a[i] for i in range(3)]
        length = math.sqrt(sum(v*v for v in direction))
        direction = [v/length for v in direction]
        helper = (0, 1, 0) if abs(direction[1]) < .9 else (0, 0, 1)
        u = (direction[1]*helper[2]-direction[2]*helper[1],
             direction[2]*helper[0]-direction[0]*helper[2],
             direction[0]*helper[1]-direction[1]*helper[0])
        norm = math.sqrt(sum(v*v for v in u))
        u = [v/norm for v in u]
        v = (direction[1]*u[2]-direction[2]*u[1],
             direction[2]*u[0]-direction[0]*u[2],
             direction[0]*u[1]-direction[1]*u[0])
        rings = [[tuple(p[k]+du*u[k]*width/2+dv*v[k]*depth/2 for k in range(3))
                  for du,dv in ((-1,-1),(1,-1),(1,1),(-1,1))] for p in (a,b)]
        self.quad(*reversed(rings[0]),material)
        self.quad(*rings[1],material)
        for i in range(4):
            j = (i+1) % 4
            self.quad(rings[0][i],rings[0][j],rings[1][j],rings[1][i],material)

    def tree(self, x, z, size=1):
        self.cylinder((x,0,z),(x,4*size,z),.22*size,"ochre",6)
        self.cylinder((x,2.7*size,z),(x,6.8*size,z),2.3*size,"green",8)
        self.cylinder((x,6.8*size,z),(x,8.5*size,z),1.4*size,"green",8)

    def lamp(self, x, z):
        self.cylinder((x,0,z),(x,7,z),.10,"steel",6)
        self.box((x,7,z),(2,.18,.6),"white")

    def shelter(self, x, z, width=16, depth=4):
        for dx in (-width*.43,width*.43):
            for dz in (-depth*.35,depth*.35):
                self.box((x+dx,1.65,z+dz),(.16,3.3,.16),"steel")
        self.box((x,3.45,z),(width,.3,depth),"steel")
        self.box((x,1.6,z-depth*.4),(width*.90,2.8,.12),"glass")
        self.box((x,.65,z),(width*.6,.18,.5),"white")
