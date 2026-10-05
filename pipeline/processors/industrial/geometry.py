"""범용 공단의 회전체와 작업 발판 기하."""

import math
from taehwagang.geometry import StationMesh


class IndustrialMesh(StationMesh):
    """공통 정적 메시 작성기를 재사용하는 산업 설비 기하."""

    def sphere(self, center, radius, rise=None, hemisphere=False):
        rise = radius if rise is None else rise
        rings, segments = (8 if hemisphere else 16), 24
        lo, hi = (0, math.pi/2) if hemisphere else (-math.pi/2, math.pi/2)
        def point(latitude, angle):
            return (center[0]+radius*math.cos(latitude)*math.cos(angle),
                    center[1]+rise*math.sin(latitude),
                    center[2]+radius*math.cos(latitude)*math.sin(angle))
        for row in range(rings):
            a,b=lo+(hi-lo)*row/rings,lo+(hi-lo)*(row+1)/rings
            for col in range(segments):
                t,u=col*2*math.pi/segments,(col+1)*2*math.pi/segments
                self.quad(point(a,t),point(b,t),point(b,u),point(a,u),"steel")

    def tube(self, base, height, bottom_radius, top_radius, thickness=.3):
        segments=24
        for i in range(segments):
            a,b=i*2*math.pi/segments,(i+1)*2*math.pi/segments
            def p(radius,y,angle): return (base[0]+radius*math.cos(angle),y,base[1]+radius*math.sin(angle))
            bottom_a,bottom_b=p(bottom_radius,0,a),p(bottom_radius,0,b)
            top_a,top_b=p(top_radius,height,a),p(top_radius,height,b)
            self.quad(bottom_a,top_a,top_b,bottom_b,"white")
            inner_a,inner_b=p(top_radius-thickness,height,a),p(top_radius-thickness,height,b)
            self.quad(top_a,inner_a,inner_b,top_b,"steel")
            self.quad(inner_a,p(top_radius-thickness,height-3,a),
                      p(top_radius-thickness,height-3,b),inner_b,"dark")
        self.cylinder((base[0],height-3.1,base[1]),(base[0],height-3,base[1]),top_radius-thickness,"dark",24)

    def platform(self, radius, y):
        self.cylinder((0,y-.18,0),(0,y,0),radius,"dark",24)
        for i in range(16):
            angle=i*math.pi/8
            x,z=radius*math.cos(angle),radius*math.sin(angle)
            self.cylinder((x,y,z),(x,y+1.1,z),.05,"steel",6)
            next_angle=(i+1)*math.pi/8
            self.cylinder((x,y+1.1,z),(radius*math.cos(next_angle),y+1.1,radius*math.sin(next_angle)),.045,"steel",6)

    def chimney_band(self, y, height, bottom_radius, top_radius):
        for i in range(24):
            a,b=i*math.pi/12,(i+1)*math.pi/12
            def p(radius,level,angle): return (radius*math.cos(angle),level,radius*math.sin(angle))
            self.quad(p(bottom_radius,y,a),p(top_radius,y+height,a),
                      p(top_radius,y+height,b),p(bottom_radius,y,b),"red")

    def ladder(self,x,z,top):
        for dx in (-.35,.35): self.cylinder((x+dx,0,z),(x+dx,top,z),.055,"steel",6)
        for i in range(int(top/.4)):
            self.cylinder((x-.35,.25+i*.4,z),(x+.35,.25+i*.4,z),.045,"steel",6)
