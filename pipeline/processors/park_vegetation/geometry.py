"""작은 불투명 입체 부재로 군락을 만든다."""
import math
from taehwagang.geometry import StationMesh

PALETTE={"leaf":(.24,.40,.16),"light_leaf":(.40,.53,.22),"stem":(.28,.36,.12),
         "flower":(.82,.57,.24),"pink":(.70,.36,.48),"dry":(.57,.49,.28),
         "stone":(.47,.49,.43),"stone_dark":(.35,.38,.34)}


class ParkMesh(StationMesh):
    def blade(self,base,height,width,angle,lean=0.12,material="leaf"):
        x,y,z=base
        dx,dz=math.cos(angle),math.sin(angle)
        a=(x-dz*width/2,y,z+dx*width/2)
        b=(x+dz*width/2,y,z-dx*width/2)
        c=(x+dx*lean,y+height,z+dz*lean)
        d=(x+dx*width*.22,y+height*.35,z+dz*width*.22)
        # 사면체: 뒷면 복제와 알파 겹침 없이 어느 방향에서도 실루엣을 남긴다.
        for p,q,r in ((a,c,b),(a,d,c),(b,c,d),(a,b,d)):
            self.triangle(p,q,r,material)

    def bloom(self,center,radius,material="flower",height=None):
        x,y,z=center
        h=radius*.5 if height is None else height
        ring=[(x+radius*math.cos(i*math.pi/2),y,z+radius*math.sin(i*math.pi/2)) for i in range(4)]
        for i in range(4):
            j=(i+1)%4
            self.triangle((x,y+h,z),ring[j],ring[i],material)
            self.triangle((x,y-h,z),ring[i],ring[j],material)

    def rock(self,center,size,segments=8,rings=3,phase=0):
        x,y,z=center; w,h,d=size
        if rings==1:
            points=[(x+w*.5*math.cos(i*math.pi/2),y+h*.45,z+d*.5*math.sin(i*math.pi/2)) for i in range(4)]
            for i in range(4):
                j=(i+1)%4
                self.triangle((x,y+h,z),points[j],points[i],"stone")
                self.triangle((x,y,z),points[i],points[j],"stone_dark")
            return
        levels=[(0,.73),(.44,1),(.82,.55)][:rings]
        profiles=[]
        for height,radius in levels:
            profiles.append([(x+w*.5*radius*math.cos(i*math.tau/segments)*(1+.1*math.sin(i*2.7+phase)),
                              y+h*height,z+d*.5*radius*math.sin(i*math.tau/segments)) for i in range(segments)])
        for a,b in zip(profiles,profiles[1:]):
            for i in range(segments):
                j=(i+1)%segments
                self.quad(a[i],b[i],b[j],a[j],"stone")
        for i in range(segments):
            j=(i+1)%segments
            self.triangle((x,y+h,z),profiles[-1][j],profiles[-1][i],"stone")
            self.triangle((x,y,z),profiles[0][i],profiles[0][j],"stone_dark")
