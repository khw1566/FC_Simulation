"""고래 형상을 참고한 신축 역사 외관과 출입부."""

import math
from .geometry import StationMesh


def build(config):
    mesh = StationMesh()
    width, depth = config["station_width_m"], config["station_depth_m"]
    mesh.box((0,.4,0),(width+6,.8,depth+6),"steel")
    mesh.box((0,8.4,0),(width,16,depth),"white")
    # 큰 유리 면과 수직 멀리언으로 박스형 기반과 외피를 구분한다.
    for side in (-1,1):
        mesh.box((0,9,side*(depth/2+.06)),(width-5,13,.12),"glass")
        for x in range(-52,53,12):
            mesh.box((x,9,side*(depth/2+.16)),(.18,13,.22),"steel")
        for y in (4,8,12,15):
            mesh.box((0,y,side*(depth/2+.20)),(width-4,.14,.26),"steel")
    for side in (-1,1):
        mesh.box((side*(width/2+.06),9,0),(.12,12,depth-5),"glass")
    # 긴 외피의 파형 윤곽과 비스듬한 리브는 공개 외관의 단순화 표현이다.
    def roof(x):
        return 19+7*math.cos((x+10)/width*math.pi*.85)
    for i in range(8):
        a, b = -width/2+i*width/8, -width/2+(i+1)*width/8
        mesh.profile([(a,16.1),(b,16.1),(b,roof(b)),(a,roof(a))],
                     depth/2+1.8,-depth/2-1.5,"white" if i%4 < 2 else "steel")
        mesh.beam((a,7,depth/2+.4),(a+2.7,roof(a),depth/2+2),.5,.75,"white")
    mesh.box((0,5,depth/2+5),(44,.5,9),"steel")
    for x in (-20,-10,10,20):
        mesh.box((x,2.5,depth/2+7),(.35,5,.35),"steel")
    for x in (-12,-4,4,12):
        mesh.box((x,2.3,depth/2+.4),(6.5,4,.25),"dark")
        mesh.box((x,2.3,depth/2+.58),(5.9,3.7,.08),"glass")
    # 낮은 출입 계단과 양쪽 경사로. 정상부 높이는 역사 기단과 동일하다.
    for i in range(4):
        mesh.box((0,(i+1)*.1,depth/2+11-i*.8),(40,(i+1)*.2,.8),"white")
    for side in (-1,1):
        x = side*31
        mesh.profile([(x-2,0),(x+2,0),(x+2,.8),(x-2,.8)],depth/2+3,depth/2-1,"steel")
        mesh.beam((x,.1,depth/2+15),(x,.8,depth/2+3),4,.18,"white")
        for dx in (-2,2):
            mesh.beam((x+dx,1.1,depth/2+15),(x+dx,1.8,depth/2+3),.06,.06,"steel")
    # 선로 쪽 연결 통로. 승강장 계단은 별도 모듈에 둔다.
    mesh.box((0,7,-29),(68,3,20),"white")
    mesh.box((0,8.65,-29),(70,.3,21),"steel")
    mesh.box((0,7,-39.1),(60,2,.12),"glass")
    mesh.box((0,16.5,depth/2+2.2),(32,2,.18),"dark")
    return mesh
