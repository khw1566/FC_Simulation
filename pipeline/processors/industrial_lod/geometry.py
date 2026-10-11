"""실루엣에 필요한 낮은 면수 회전체와 외피만 만든다."""
import math
from taehwagang.geometry import StationMesh


class DistantMesh(StationMesh):
    def __init__(self,level):
        super().__init__()
        self.level=level
        self.segments=6 if level==1 else 4

    def cylinder(self,a,b,radius,material="steel",segments=None):
        super().cylinder(a,b,radius,"steel",self.segments)

    def box(self,center,size,material="steel"):
        super().box(center,size,"steel")

    def beam(self,a,b,width,depth,material="steel"):
        super().beam(a,b,width,depth,"steel")

    def profile(self,points,front,back,material="steel"):
        super().profile(points,front,back,"steel")

    def shell(self,center,levels,cap=True):
        x,z=center
        rings=[[(x+r*math.cos(i*math.tau/self.segments),y,z+r*math.sin(i*math.tau/self.segments))
                for i in range(self.segments)] for y,r in levels]
        for lower,upper in zip(rings,rings[1:]):
            for i in range(self.segments):
                j=(i+1)%self.segments
                self.quad(lower[i],upper[i],upper[j],lower[j],"steel")
        if cap:
            for ring,(y,r) in ((rings[0],levels[0]),(rings[-1],levels[-1])):
                for i in range(self.segments):
                    j=(i+1)%self.segments
                    if ring is rings[0]:
                        self.triangle((x,y,z),ring[i],ring[j],"steel")
                    else:
                        self.triangle((x,y,z),ring[j],ring[i],"steel")

    def sphere(self,center,radius,rise=None):
        rise=radius if rise is None else rise
        rings=4 if self.level==1 else 2
        levels=[(-math.pi/2+i*math.pi/rings) for i in range(rings+1)]
        for a,b in zip(levels,levels[1:]):
            for i in range(self.segments):
                t,u=i*math.tau/self.segments,(i+1)*math.tau/self.segments
                def p(lat,angle):
                    return (center[0]+radius*math.cos(lat)*math.cos(angle),
                            center[1]+rise*math.sin(lat),center[2]+radius*math.cos(lat)*math.sin(angle))
                self.quad(p(a,t),p(b,t),p(b,u),p(a,u),"steel")
