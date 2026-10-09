"""6m·12m 게임용 컨테이너와 저다각형 적재 묶음. 실측 규격 아님."""
from .asset import HarborAsset

COLORS=("red","blue","green","ochre")


def unit(mesh,center,length,color,door=True):
    x,y,z=center
    mesh.box((x,y+1.3,z),(2.4,2.6,length),color)
    if door:
        for dx in (-.58,.58): mesh.box((x+dx,y+1.3,z+length/2+.015),(1.08,2.35,.03),"concrete_dark")
        for dx in (-.12,.12): mesh.box((x+dx,y+1.3,z+length/2+.04),(.04,2.1,.025),"steel")


def single(length,color):
    a=HarborAsset(f"container_{length}m_{color}",f"컨테이너 {length}m · { {'red':'적색','blue':'청색','green':'녹색','ochre':'황토색'}[color]}","container")
    unit(a.mesh,(0,0,0),length,color)
    a.marker("StackTop",(0,2.6,0),"container_stack_2p4",width=2.4)
    a.box_collision((0,1.3,0),(2.4,2.6,length))
    a.extra.update(length_m=length,width_m=2.4,height_m=2.6,stack_pitch_y_m=2.6,iso_dimensions=False,instancing_recommended=True)
    return a


def stack(columns,rows,levels,length=6,stagger=False):
    key=f"container_stack_{columns}x{rows}x{levels}"+("_stagger" if stagger else "")
    a=HarborAsset(key,f"컨테이너 적재 {columns}×{rows}×{levels}"+(" 엇갈림" if stagger else ""),"container_stack")
    for row in range(rows):
        for col in range(columns):
            x=(col-(columns-1)/2)*2.65; z=(row-(rows-1)/2)*(length+.3)
            for level in range(levels):
                shift=.65 if stagger and level%2 else 0
                unit(a.mesh,(x,level*2.6,z+shift),length,COLORS[(col+row+level)%4],door=row==rows-1)
            a.box_collision((x,levels*1.3,z),(2.4,levels*2.6,length+.65 if stagger else length))
    a.marker("StackTop",(0,levels*2.6,0),"container_group_top")
    a.extra.update(container_count=columns*rows*levels,levels=levels,container_length_m=length,instancing_recommended=True,iso_dimensions=False)
    return a


def build():
    return [single(n,c) for n in (6,12) for c in ("red","blue","green")]+[stack(*s) for s in ((2,1,2),(2,2,2),(3,2,3),(2,1,3))]+[stack(2,1,3,stagger=True)]
