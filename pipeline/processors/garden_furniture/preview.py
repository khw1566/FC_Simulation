"""모델 메시를 깊이 버퍼로 직접 투영하는 비교 미리보기."""
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from .mesh import PALETTE


def render(models,path):
    image=Image.new('RGB',(1680,1800),(23,26,28))
    pixels=np.array(image)
    depth=np.full((1800,1680),-np.inf)
    def project(p):
        x,y,z=p
        return (.82*x-.57*z,-.32*x-.78*y-.46*z,-.44*x+.55*y-.68*z)
    for index,(label,tier,mesh) in enumerate(models):
        row,col=divmod(index,2)
        cx,cy=420+840*col,220+260*row
        points=[project(p) for f in mesh.faces for p in f[:3]]
        extent=[(min(p[k] for p in points),max(p[k] for p in points)) for k in range(2)]
        scale=min(690/(extent[0][1]-extent[0][0]),160/(extent[1][1]-extent[1][0]))
        mid=[(a+b)/2 for a,b in extent]
        for face in mesh.faces:
            n=face[3]
            if sum(n[k]*(-.44,.55,-.68)[k] for k in range(3))<=0: continue
            shade=.45+.55*max(0,sum(n[k]*(-.4,.85,-.35)[k] for k in range(3)))
            color=tuple(int(255*c*shade) for c in PALETTE[face[4]])
            vertices=[(cx+(project(p)[0]-mid[0])*scale,cy+(project(p)[1]-mid[1])*scale,project(p)[2]) for p in face[:3]]
            x0=max(0,int(min(p[0] for p in vertices)))
            x1=min(1679,int(max(p[0] for p in vertices))+1)
            y0=max(0,int(min(p[1] for p in vertices)))
            y1=min(1799,int(max(p[1] for p in vertices))+1)
            a,b,c=vertices
            den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-8: continue
            yy,xx=np.mgrid[y0:y1+1,x0:x1+1]
            u=((b[1]-c[1])*(xx+.5-c[0])+(c[0]-b[0])*(yy+.5-c[1]))/den
            v=((c[1]-a[1])*(xx+.5-c[0])+(a[0]-c[0])*(yy+.5-c[1]))/den
            w=1-u-v
            z=u*a[2]+v*b[2]+w*c[2]
            target=depth[y0:y1+1,x0:x1+1]
            mask=(u>=0)&(v>=0)&(w>=0)&(z>target)
            target[mask]=z[mask]
            pixels[y0:y1+1,x0:x1+1][mask]=color
    image=Image.fromarray(pixels)
    draw=ImageDraw.Draw(image)
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',22)
    title=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',32)
    draw.text((40,24),'태화강 국가정원 시설물 · 근경 / 원경 별도 에셋',font=title,fill=(238,238,233))
    draw.text((40,72),'범용 배치용 디자인 · 외부 텍스처 없음 · 각 모델 독립 축척 · 단위 m',font=font,fill=(177,185,185))
    for index,(label,tier,mesh) in enumerate(models):
        row,col=divmod(index,2)
        draw.text((40+840*col,315+260*row),f'{label}  /  {"원경" if tier=="far" else "근경"}  /  {len(mesh.faces)} tris',font=font,fill=(218,223,222))
    image.save(path)
