"""보·어도·배수문·호안의 정적 단면. 미확인 치수는 추정으로 분리한다."""
import math
from vessels.mesh import VesselMesh

PALETTE={'concrete':(.47,.48,.45),'stone':(.37,.39,.36),'steel':(.25,.29,.28),
         'deck':(.42,.43,.40),'earth':(.33,.35,.27),'opening':(.045,.055,.05)}


def build(spec, survey, hydro):
    mesh=VesselMesh()
    kind=spec['kind']
    if 'axis_lonlat' in spec:
        a,b=[survey.world(*p) for p in spec['axis_lonlat']]
        length=math.dist(a,b)
        anchor=[(a[0]+b[0])/2,0,(a[1]+b[1])/2]
        yaw=math.atan2(-(b[1]-a[1]),b[0]-a[0])
        anchor[1]=hydro.vertex(round(anchor[0],5),round(anchor[2],5))[1]-.10 if kind=='weir' else .6
    elif kind=='basin':
        center=survey.basins[0].centroid
        anchor=[center.x,.6,center.y]; length=0.;yaw=0.
    else:
        anchor=[0,0,0];length=spec['length_m_estimate'];yaw=0.
    if kind=='weir':
        slot=length*.12; gap=spec['fishway_width_m_estimate']
        for left,right in [(-length/2,slot-gap/2),(slot+gap/2,length/2)]:
            mesh.box(((left+right)/2,-.65,0),(right-left,1.3,2.4),'concrete')
            mesh.quad((left,0,1.2),(right,0,1.2),(right,-1.2,5),(left,-1.2,5),'concrete')
            mesh.box(((left+right)/2,-1.32,8),(right-left,.25,7),'stone')
        for x in [slot-gap/2-.22,slot+gap/2+.22]:
            mesh.box((x,-.5,4.5),(.44,1.4,15),'concrete')
        mesh.box((slot,-1.15,4.5),(gap,.28,15),'stone')
        for i in range(6):
            side=-1 if i%2 else 1
            mesh.box((slot+side*.45,-.87+i*.08,-2+i*2.3),(gap*.58,.50,.32),'concrete')
    elif kind=='gate':
        count=4
        width=length/count
        mesh.box((0,-.8,0),(length+4,1.6,8),'concrete')
        mesh.box((0,3.4,0),(length+4,.6,5),'deck')
        for i in range(count+1):
            mesh.box((-length/2+width*i,1.5,0),(1.4,4,6),'concrete')
        for i in range(count):
            x=-length/2+width*(i+.5)
            mesh.box((x,1.1,0),(width-1.5,2.9,.35),'steel')
            mesh.box((x,4.1,0),(2.8,1.1,2.3),'steel')
            for offset in [-width*.22,width*.22]:
                mesh.box((x+offset,1.1,-.23),(.12,2.9,.15),'concrete')
        for z in [-2.3,2.3]:
            mesh.box((0,4.3,z),(length+4,.09,.09),'steel')
            for i in range(math.ceil(length/4)+1):
                mesh.box((-length/2+length*i/math.ceil(length/4),3.95,z),(.09,.9,.09),'steel')
    elif kind=='basin':
        polygons=[part for water in survey.basins for part in (water.geoms if hasattr(water,'geoms') else [water])]
        for polygon in polygons:
            coordinates=list(polygon.exterior.coords)
            for a,b in zip(coordinates,coordinates[1:]):
                dx,dz=b[0]-a[0],b[1]-a[1]; norm=math.hypot(dx,dz)
                if norm<.05: continue
                nx,nz=-dz/norm,dx/norm
                ya=max(.5,float(survey.height(*a))-.6);yb=max(.5,float(survey.height(*b))-.6)
                def p(v,y,offset):return(v[0]-anchor[0]+nx*offset,y,v[1]-anchor[2]+nz*offset)
                mesh.quad(p(a,ya,.8),p(b,yb,.8),p(b,-1.55,3),p(a,-1.55,3),'stone')
                mesh.quad(p(a,ya,-.8),p(b,yb,-.8),p(b,yb,.8),p(a,ya,.8),'earth')
    elif kind=='outlet':
        mesh.box((0,-.3,0),(length+2,.6,8),'concrete')
        for x in [-length/2,0,length/2]: mesh.box((x,1.5,0),(.5,3,4),'concrete')
        mesh.box((0,3.15,0),(length+1,.5,4),'concrete')
        mesh.box((0,1.2,-1.9),(length,2.6,.12),'opening')
        for i in range(19): mesh.box((-length/2+length*i/18,1.3,2.03),(.05,2.5,.08),'steel')
    else:
        mesh.quad((-10,0,-2),(10,0,-2),(10,-3,4),(-10,-3,4),'stone')
        mesh.box((0,.05,-3.5),(20,.3,3),'deck')
        for i in range(5):mesh.box((-8+4*i,.65,-4.9),(.1,1.3,.1),'steel')
        mesh.box((0,1.3,-4.9),(20,.1,.1),'steel')
    return mesh,{'anchor_world_m':anchor,'axis_yaw_rad':yaw,'length_m':length,
                 'placement_status':'unplaced' if spec['status']=='reusable_unplaced' else 'map_80km_research_estimate'}
