"""기존 3열 배관과 호환되는 플랜트 랙·교차·높이 전환."""

from industrial import pipes
from industrial.geometry import IndustrialMesh

PORTS={
    'rack_straight':[([-12,5,0],[-1,0,0]),([12,5,0],[1,0,0])],
    'rack_elbow':[([-12,5,0],[-1,0,0]),([0,5,12],[0,0,1])],
    'rack_tee':[([-12,5,0],[-1,0,0]),([12,5,0],[1,0,0]),([0,5,12],[0,0,1])],
    'rack_cross':[([-12,5,0],[-1,0,0]),([12,5,0],[1,0,0]),([0,5,-12],[0,0,-1]),([0,5,12],[0,0,1])],
    'rack_riser':[([-12,5,0],[-1,0,0]),([12,9,0],[1,0,0])],
    'rack_double':[([-12,5,0],[-1,0,0]),([12,5,0],[1,0,0]),([-12,9,0],[-1,0,0]),([12,9,0],[1,0,0])],
}
LABELS={'rack_straight':'배관 랙 직선','rack_elbow':'배관 랙 곡관','rack_tee':'배관 랙 분기',
        'rack_cross':'배관 랙 교차','rack_riser':'배관 랙 높이 전환','rack_double':'배관 랙 2층'}


def build(kind):
    aliases={'rack_straight':'pipeline_straight','rack_elbow':'pipeline_elbow','rack_tee':'pipeline_tee'}
    if kind in aliases: return pipes.build(aliases[kind])
    mesh=IndustrialMesh()
    for z in (-1.1,0,1.1):
        if kind=='rack_riser':
            points=[(-12,5,z),(-4,5,z),(4,9,z),(12,9,z)]
            for a,b in zip(points,points[1:]): mesh.cylinder(a,b,.32,'steel',12)
        else:
            mesh.cylinder((-12,5,z),(12,5,z),.32,'steel',12)
            if kind=='rack_double': mesh.cylinder((-12,9,z),(12,9,z),.32,'steel',12)
            # 교차는 같은 높이의 연결 헤더이다. 독립 관의 입체 교차는 2층 랙 사용.
            if kind=='rack_cross': mesh.cylinder((z,5,-12),(z,5,12),.32,'steel',12)
    for x in (-9,9):
        height=9 if kind=='rack_double' or kind=='rack_riser' and x>0 else 5
        for z in (-1.8,1.8): mesh.box((x,height/2,z),(.3,height,.3),'steel')
        for y in ([5,9] if kind=='rack_double' else [height]): mesh.box((x,y-.4,0),(.5,.3,4.2),'steel')
    if kind=='rack_cross':
        for z in (-9,9):
            for x in (-1.8,1.8): mesh.box((x,2.5,z),(.3,5,.3),'steel')
            mesh.box((0,4.6,z),(4.2,.3,.5),'steel')
    return mesh
