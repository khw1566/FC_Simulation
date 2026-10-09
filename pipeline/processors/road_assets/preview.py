"""실제 생성 메시를 독립 이미지로 투영하는 경량 프리뷰."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from road_assets.mesh import PALETTE, RoadMesh


def render(models, path, title, columns=4, cell_width=400, cell_height=320):
    cw,ch=cell_width,cell_height
    pw,ph=cw-20,ch-70
    image=Image.new("RGB",(cw*columns,70+ch*math.ceil(len(models)/columns)),(23,23,23))
    draw=ImageDraw.Draw(image)
    font=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",19)
    heading=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",25)
    draw.text((22,17),title,font=heading,fill=(240,240,240))
    view=(.42,.78,.47)
    def project(p):
        x,y,z=p
        return (.85*x-.52*z,.40*x-.70*y+.66*z,sum(p[i]*view[i] for i in range(3)))
    for index,(label,mesh) in enumerate(models):
        left=(index%columns)*cw; top=70+(index//columns)*ch
        points=[project(p) for f in mesh.faces for p in f[:3]]
        ranges=[(min(p[k] for p in points),max(p[k] for p in points)) for k in (0,1)]
        scale=min((pw-30)/max(.1,ranges[0][1]-ranges[0][0]),(ph-15)/max(.1,ranges[1][1]-ranges[1][0]))
        mid=[sum(pair)/2 for pair in ranges]
        pixels=np.full((ph,pw,3),31,dtype=np.uint8); depth=np.full((ph,pw),-np.inf)
        for face in mesh.faces:
            if sum(face[3][i]*view[i] for i in range(3))<=0: continue
            shade=.5+.5*max(0,sum(face[3][i]*(-.3,.88,.36)[i] for i in range(3)))
            color=tuple(int(255*c*shade) for c in PALETTE[face[4]])
            vertices=[(pw/2+(project(p)[0]-mid[0])*scale,ph/2+(project(p)[1]-mid[1])*scale,project(p)[2]) for p in face[:3]]
            a,b,c=vertices
            x0,x1=max(0,int(min(p[0] for p in vertices))),min(pw-1,int(max(p[0] for p in vertices))+1)
            y0,y1=max(0,int(min(p[1] for p in vertices))),min(ph-1,int(max(p[1] for p in vertices))+1)
            denominator=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(denominator)<1e-8 or x0>x1 or y0>y1: continue
            yy,xx=np.mgrid[y0:y1+1,x0:x1+1]
            u=((b[1]-c[1])*(xx+.5-c[0])+(c[0]-b[0])*(yy+.5-c[1]))/denominator
            v=((c[1]-a[1])*(xx+.5-c[0])+(a[0]-c[0])*(yy+.5-c[1]))/denominator
            w=1-u-v; z=u*a[2]+v*b[2]+w*c[2]
            target=depth[y0:y1+1,x0:x1+1]; mask=(u>=0)&(v>=0)&(w>=0)&(z>target)
            target[mask]=z[mask]; pixels[y0:y1+1,x0:x1+1][mask]=color
        image.paste(Image.fromarray(pixels),(left+10,top+10))
        draw.text((left+15,top+ch-54),label,font=font,fill=(235,235,235))
        draw.text((left+15,top+ch-27),f"{len(mesh.faces):,} 삼각형 / 독립 축척",font=font,fill=(150,150,150))
    image.save(path)


def combine(placements, meshes):
    result=RoadMesh()
    for item in placements:
        mesh=meshes[item["asset"]]; a=item["rotation_y"]; p=item["position_m"]
        def transform(v,normal=False):
            q=(v[0]*math.cos(a)+v[2]*math.sin(a),v[1],-v[0]*math.sin(a)+v[2]*math.cos(a))
            return q if normal else tuple(q[i]+p[i] for i in range(3))
        for face in mesh.faces:
            result.faces.append((*[transform(v) for v in face[:3]],transform(face[3],True),face[4]))
    return result
