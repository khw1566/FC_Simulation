"""시설 형상에 맞춘 작업등·창문·보행등·상단 표식등 배치."""

import math


def layout(key,meta):
    fixtures=[]; lights=[]
    def bulb(p,tint='warm',size=.45): fixtures.append(('sphere',p,(size,size,size),tint,0))
    def strip(p,size,tint='warm',angle=0): fixtures.append(('box',p,size,tint,angle))
    def light(p,tint='warm',energy=1.6,radius=15,rotation=None):
        lights.append({'position':p,'tint':tint,'energy':energy,'range':radius,'rotation':rotation})
    def ring(radius,y,count=8,tint='warm'):
        for i in range(count):
            a=i*math.tau/count; p=(radius*math.cos(a),y,radius*math.sin(a))
            bulb(p,tint)
            strip(p,(.18,.18,min(3.0,radius*.65)),tint,-a)
    def uplight(x,z,height,tint='cool'):
        bulb((x,1.2,z),tint,.4)
        pitch=math.atan2(max(8,height*.6)-1.3,math.hypot(x,z))
        light((x,1.3,z),tint,4.2,min(110,height+12),(pitch,math.atan2(x,z),0))
    height=meta['aabb_max_m'][1]
    if key.startswith('factory_') or key=='shipbuilding_hangar':
        dimensions={'factory_gable':(48,72),'factory_sawtooth':(64,88),'factory_flat':(44,60),
                    'shipbuilding_hangar':(100,180)}
        width,length=dimensions[key]
        rows=(4.5,8) if key.startswith('factory_') else (31,)
        for side in (-1,1):
            for row in rows:
                for i,z in enumerate(range(-int(length/2)+7,int(length/2)-4,8)):
                    if i%4==1: continue
                    strip((side*(width/2+.22),row,z),(.06,1.15,3.8),'warm' if i%3 else 'cool')
            for z in (-length*.3,length*.3):
                bulb((side*(width/2+.7),6,z),'cool',.5)
            light((side*(width/2+1.4),5,length*.25),'cool',1.6,26 if width<80 else 36)
        for x in (-width*.25,width*.25):
            bulb((x,7 if width<80 else 33,length/2+1),'warm',.5)
            light((x,6 if width<80 else 27,length/2+1.5),'warm',2,22 if width<80 else 45)
        if key=='shipbuilding_hangar': strip((0,34.2,90.6),(72,.18,.16),'cool')
    elif key in ('liquid_storage_tank','lpg_sphere'):
        radius=16.2 if key=='liquid_storage_tank' else 9.2
        ring(radius,16.9 if key=='liquid_storage_tank' else 13,12,'warm')
        for x in (-radius-1,radius+1): uplight(x,3,22,'cool')
        bulb((0,height+.2,0),'red',.45)
    elif key in ('tower_crane','gantry_crane'):
        end=60 if key=='tower_crane' else 48
        start=-18 if key=='tower_crane' else -48
        for x in range(start,end+1,6):
            p=(x,53.4,1.5 if key=='tower_crane' else 4)
            bulb(p,'warm'); strip(p,(3.8,.2,.18),'warm')
        for x in (start,end): bulb((x,57,0),'red',.5)
        bulb((0,height+.3,0),'red',.5)
        for x in ((-8,30) if key=='tower_crane' else (-30,30)):
            light((x,51,2),'warm',2.5,32, (-math.pi/2,0,0))
    elif key.startswith('pipeline_') or key.startswith('rack_'):
        for x in (-9,9):
            y=9.5 if key=='rack_double' or key=='rack_riser' and x>0 else 5.5
            bulb((x,y,1.8),'warm')
            strip((x,y,1.8),(.15,.18,1.5),'warm')
        if key in ('pipeline_tee','pipeline_elbow','rack_tee','rack_elbow','rack_cross'): bulb((1.8,5.5,9),'cool')
        light((0,4,1.7),'warm',1.3,11)
    elif key=='cooling_fan_bank':
        for x in (-9,0,9):
            for z in (-7,7): bulb((x,4.8,z),'cool')
        for x in (-12,12): light((x,3.5,7),'cool',1.5,15)
    elif key=='cooling_tower':
        ring(20.5,4.7,12,'warm'); ring(13.3,50.2,12,'cool')
        for x in (-22,22): uplight(x,0,50,'cool')
    elif key=='transmission_tower':
        for x in (-12,12): bulb((x,25.8,0),'red',.4)
        bulb((0,46.5,0),'red',.5)
        uplight(8,0,46,'cool')
    else:
        levels={'distillation_tower':[9,19,29,38],'industrial_chimney':[36],
                'stack_concrete':[42],'stack_steel':[18,35,50],'stack_triple':[12,28,44,58],
                'flare_lattice':[18,42,66],'process_column':[8,17,26,35,44],
                'scrubber_tower':[8,17,25]}.get(key,[height*.5])
        radius={'distillation_tower':4.5,'industrial_chimney':4.2,'stack_concrete':5.3,
                'stack_steel':3.2,'flare_lattice':2.2,'process_column':4.7,'scrubber_tower':5.1}.get(key,3)
        if key=='stack_triple':
            for y in levels:
                for x in (-6,-3,0,3,6):
                    bulb((x,y+.8,2.3),'warm')
                    strip((x,y+.8,2.3),(2.2,.18,.15),'warm')
            for x in (-4,0,4): bulb((x,62.3,0),'red',.42)
        else:
            for y in levels: ring(radius,y+.8,6,'warm')
            bulb((0,height+.2,0),'red',.45)
        uplight(radius+1.2,0,height,'cool')
        uplight(-radius-1.2,0,height,'warm')
        light((0,levels[len(levels)//2]+1,radius+.5),'warm',1.3,12)
    return fixtures,lights
