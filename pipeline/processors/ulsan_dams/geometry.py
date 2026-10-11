"""공식 길이·높이와 명시적인 추정 단면으로 댐 본체를 만든다."""
import math
from vessels.mesh import VesselMesh

PALETTE = {"rock": (.48,.49,.46), "concrete": (.64,.65,.63),
           "earth": (.35,.40,.28), "road": (.24,.25,.25), "rail": (.70,.71,.69)}


def build(spec, policy, far=False):
    mesh = VesselMesh()
    length, height = spec["official_length_m"], spec["official_height_m"]
    half = policy["crest_width_m_estimate"] / 2
    upstream = half + height * policy["upstream_slope_estimate"]
    downstream = half + height * policy["downstream_slope_estimate"]
    sections = math.ceil(length/10)
    slope_steps = math.ceil(max(upstream,downstream)/10)
    material = "earth" if spec["type"] == "EF" else "rock"
    face_material = "concrete" if spec["type"] == "CFRD" else "rock"
    # 단면의 바닥 폭·사면비는 시각화용 추정이다. 공식 제원과 별도로 기록한다.
    for i in range(sections):
        a,b = -length/2+length*i/sections, -length/2+length*(i+1)/sections
        ta=math.sin(math.pi*i/sections)**.6
        tb=math.sin(math.pi*(i+1)/sections)**.6
        mesh.quad((a,0,half),(b,0,half),(b,0,-half),(a,0,-half),"road")
        for step in range(slope_steps):
            t0,t1=step/slope_steps,(step+1)/slope_steps
            y0,y1=-height*t0,-height*t1
            ua0,ua1=-half-(upstream-half)*t0*ta,-half-(upstream-half)*t1*ta
            ub0,ub1=-half-(upstream-half)*t0*tb,-half-(upstream-half)*t1*tb
            da0,da1=half+(downstream-half)*t0*ta,half+(downstream-half)*t1*ta
            db0,db1=half+(downstream-half)*t0*tb,half+(downstream-half)*t1*tb
            mesh.quad((a,y0,ua0),(b,y0,ub0),(b,y1,ub1),(a,y1,ua1),face_material)
            mesh.quad((a,y1,da1),(b,y1,db1),(b,y0,db0),(a,y0,da0),material)
        mesh.quad((a,-height,-half-(upstream-half)*ta),(b,-height,-half-(upstream-half)*tb),
                  (b,-height,half+(downstream-half)*tb),(a,-height,half+(downstream-half)*ta),material)
    for x, reverse in [(-length/2,True),(length/2,False)]:
        points=[(x,-height,-half),(x,0,-half),(x,0,half),(x,-height,half)]
        mesh.quad(*(list(reversed(points)) if reverse else points),material)
    if not far:
        for z in [-half+.25,half-.25]:
            mesh.box((0,.65,z),(length,.10,.12),"rail")
            count=max(2,round(length/18))
            for i in range(count+1):
                mesh.box((-length/2+length*i/count,.36,z),(.12,.72,.12),"rail")
        if spec["type"] == "CFRD":
            # 표면차수벽의 큰 패널 분할만 표현한다.
            for i in range(1,sections):
                x=-length/2+length*i/sections
                taper=math.sin(math.pi*i/sections)**.6
                toe=-half-(upstream-half)*taper
                mesh.quad((x-.10,.03,-half-.03),(x+.10,.03,-half-.03),
                          (x+.10,-height+.03,toe-.03),(x-.10,-height+.03,toe-.03),"rock")
    return mesh
