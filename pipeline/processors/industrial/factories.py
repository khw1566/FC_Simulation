"""박공지붕·톱니지붕·평지붕 공장 3종."""

from .geometry import IndustrialMesh


def build(kind):
    mesh=IndustrialMesh()
    width,length,height={'factory_gable':(48,72,12),'factory_sawtooth':(64,88,10),
                         'factory_flat':(44,60,16)}[kind]
    mesh.box((0,.3,0),(width+2,.6,length+2),"deck")
    mesh.box((0,height/2+.6,0),(width,height,length),"white")
    if kind=='factory_gable':
        mesh.profile([(-width/2,height+.6),(width/2,height+.6),(0,height+6)],length/2+1,-length/2-1,"steel")
        for z in range(-30,31,12): mesh.box((0,height+3.7,z),(3,.5,3),"dark")
    elif kind=='factory_sawtooth':
        for i in range(8):
            a=-width/2+i*width/8; b=a+width/8
            mesh.profile([(a,height+.6),(b,height+.6),(b,height+4.6)],length/2+1,-length/2-1,"steel")
            mesh.box((b+.04,height+2.7,0),(.12,3,length-3),"glass")
    else:
        mesh.box((0,height+.9,0),(width+1,.6,length+1),"steel")
        for side in (-1,1): mesh.box((side*width/2,height+1.5,0),(.25,1.2,length),"white")
        for x in (-12,0,12):
            mesh.box((x,height+2,0),(7,2,10),"deck")
            mesh.box((x,height+3.1,0),(6.5,.2,9.5),"dark")
    for side in (-1,1):
        for y in (4.5,8):
            mesh.box((side*(width/2+.08),y,0),(.16,1.5,length-6),"glass")
        for z in range(-int(length/2)+5,int(length/2),8):
            mesh.box((side*(width/2+.2),height/2+.6,z),(.4,height,.4),"steel")
    for x in (-width*.25,width*.25):
        mesh.box((x,3.2,length/2+.1),(9,5.2,.2),"dark")
        for y in range(1,6): mesh.box((x,y,length/2+.24),(8.6,.06,.12),"steel")
        mesh.box((x,.65,length/2+2.2),(11,1.3,4),"deck")
    mesh.box((width*.43,1.6,length/2+.13),(1.8,2,.2),"glass")
    return mesh
