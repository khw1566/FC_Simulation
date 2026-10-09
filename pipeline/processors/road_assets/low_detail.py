"""접속 규격을 보존하는 낮은 세분화와 단색 표면 표현."""
import math
from road_assets.profiles import route


def coarse_route(shape,width):
    if shape=="straight": return route(shape,width)
    original=route(shape,width); count=3 if shape=="curve45" else 5
    end_angle=original[-1][2]
    radius=original[-1][0]/(1-math.cos(end_angle))
    return [(radius*(1-math.cos(end_angle*i/count)),
             -6+radius*math.sin(end_angle*i/count),end_angle*i/count) for i in range(count+1)]


def surface_lines(mesh,points,width,top,material,mode):
    # 개별 타일 대신 큰 구획만 표현한다.
    if mode=="wood_long":
        for offset in (-width/6,width/6):
            mesh.strip(points,offset-.014,offset+.014,top+.001,"joint")
    else:
        count=2 if mode=="large_slabs" else 4
        from road_assets.surfaces import sample,path_length
        length=path_length(points)
        for i in range(1,count):
            mesh.patch(sample(points,length*i/count),0,width-.05,.028,top+.001,"joint")
