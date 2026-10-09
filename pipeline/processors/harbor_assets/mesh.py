"""무광 단색 항구 기하. 기본 회전체는 6~8면만 사용한다."""
import math
from taehwagang.geometry import StationMesh
from custom_lowpoly.glb import export

PALETTE = {"concrete": (.58,.59,.57), "concrete_dark": (.42,.44,.43), "asphalt": (.20,.21,.22),
           "white": (.86,.87,.84), "steel": (.39,.43,.44), "dark": (.10,.13,.14),
           "red": (.60,.19,.15), "green": (.23,.43,.32), "blue": (.24,.36,.45),
           "ochre": (.68,.53,.23), "yellow": (.82,.69,.23), "glass": (.13,.23,.27),
           "lens_red": (.85,.22,.16), "lens_green": (.25,.75,.38), "lens_warm": (.92,.83,.59)}


class HarborMesh(StationMesh):
    """기존의 경량 GLB 작성기를 재사용하는 항구용 메시."""

    def cylinder(self, a, b, radius, material, segments=8):
        super().cylinder(a,b,radius,material,min(8,segments))

    def cone(self,a,b,bottom,top,material,segments=8):
        axis=tuple(b[i]-a[i] for i in range(3)); length=math.sqrt(sum(v*v for v in axis))
        axis=tuple(v/length for v in axis)
        helper=(0,1,0) if abs(axis[1])<.9 else (1,0,0)
        u=(axis[1]*helper[2]-axis[2]*helper[1],axis[2]*helper[0]-axis[0]*helper[2],axis[0]*helper[1]-axis[1]*helper[0])
        norm=math.sqrt(sum(v*v for v in u)); u=tuple(v/norm for v in u)
        v=(axis[1]*u[2]-axis[2]*u[1],axis[2]*u[0]-axis[0]*u[2],axis[0]*u[1]-axis[1]*u[0])
        rings=[[tuple(point[k]+radius*(u[k]*math.cos(i*math.tau/segments)+v[k]*math.sin(i*math.tau/segments)) for k in range(3)) for i in range(segments)] for point,radius in ((a,bottom),(b,top))]
        for i in range(segments):
            j=(i+1)%segments
            self.quad(rings[0][i],rings[0][j],rings[1][j],rings[1][i],material)
            self.triangle(a,rings[0][j],rings[0][i],material)
            self.triangle(b,rings[1][i],rings[1][j],material)

    def slab(self, polygon, top, bottom, material="concrete"):
        upper=[(x,top,z) for x,z in polygon]; lower=[(x,bottom,z) for x,z in polygon]
        # XZ 평면의 시계 방향 볼록 다각형.
        for i in range(1,len(polygon)-1):
            self.triangle(upper[0],upper[i],upper[i+1],material)
            self.triangle(lower[0],lower[i+1],lower[i],material)
        for i in range(len(polygon)):
            j=(i+1)%len(polygon)
            self.quad(lower[i],lower[j],upper[j],upper[i],material)

    def export(self,path,name):
        export(self,path,name,PALETTE)
