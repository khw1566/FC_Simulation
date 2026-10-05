"""생성 메시의 독립 카드 미리보기."""

from PIL import Image, ImageDraw, ImageFont
import numpy as np
from vessels.mesh import PALETTE


def render(models,path):
    image=Image.new('RGB',(2000,90+430*((len(models)+4)//5)),(23,23,23))
    draw=ImageDraw.Draw(image)
    title=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',28)
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',20)
    draw.text((30,20),f'범용 공단 에셋 / {len(models)}종',font=title,fill=(240,240,240))
    view=(.4472,.4204,.731)
    def project(p):
        x,y,z=p
        return (.85*x-.52*z,.22*x-.86*y+.36*z,sum(p[i]*view[i] for i in range(3)))
    for index,(key,label,mesh) in enumerate(models):
        cx,cy=200+index%5*400,285+index//5*430
        draw.rectangle((cx-185,cy-195,cx+185,cy+205),fill=(31,31,31),outline=(65,65,65))
        points=[project(p) for f in mesh.faces for p in f[:3]]
        limits=[(min(p[k] for p in points),max(p[k] for p in points)) for k in (0,1)]
        scale=min(330/(limits[0][1]-limits[0][0]),295/(limits[1][1]-limits[1][0]))
        mid=[(lo+hi)/2 for lo,hi in limits]
        pixels=np.full((320,360,3),31,dtype=np.uint8)
        depth=np.full((320,360),-np.inf)
        for face in mesh.faces:
            if sum(face[3][i]*view[i] for i in range(3))<=0: continue
            shade=.45+.55*max(0,sum(face[3][i]*(-.3,.88,.36)[i] for i in range(3)))
            color=tuple(int(255*c*shade) for c in PALETTE[face[4]])
            vertices=[(180+(project(p)[0]-mid[0])*scale,155+(project(p)[1]-mid[1])*scale,project(p)[2]) for p in face[:3]]
            a,b,c=vertices
            x0,x1=max(0,int(min(p[0] for p in vertices))),min(359,int(max(p[0] for p in vertices))+1)
            y0,y1=max(0,int(min(p[1] for p in vertices))),min(319,int(max(p[1] for p in vertices))+1)
            denominator=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(denominator)<1e-8 or x0>x1 or y0>y1: continue
            yy,xx=np.mgrid[y0:y1+1,x0:x1+1]
            u=((b[1]-c[1])*(xx+.5-c[0])+(c[0]-b[0])*(yy+.5-c[1]))/denominator
            v=((c[1]-a[1])*(xx+.5-c[0])+(a[0]-c[0])*(yy+.5-c[1]))/denominator
            w=1-u-v
            z=u*a[2]+v*b[2]+w*c[2]
            target=depth[y0:y1+1,x0:x1+1]
            mask=(u>=0)&(v>=0)&(w>=0)&(z>target)
            target[mask]=z[mask]
            pixels[y0:y1+1,x0:x1+1][mask]=color
        image.paste(Image.fromarray(pixels),(cx-180,cy-185))
        draw.text((cx-170,cy+140),label,font=font,fill=(235,235,235))
        draw.text((cx-170,cy+170),f'{len(mesh.faces):,} triangles',font=font,fill=(160,160,160))
    image.save(path)
