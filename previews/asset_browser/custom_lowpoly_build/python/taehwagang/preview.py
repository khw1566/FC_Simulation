"""깊이 버퍼로 실제 생성 메시를 투영하는 경량 미리보기."""

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from vessels.mesh import PALETTE


def render(mesh, path, title):
    width, height = 1600, 1050
    pixels = np.full((height,width,3),26,dtype=np.uint8)
    depth = np.full((height,width),-np.inf)
    view = (.4472,.4204,.731)
    def project(p):
        x,y,z = p
        return (.85*x-.52*z,.22*x-.86*y+.36*z,sum(p[i]*view[i] for i in range(3)))
    points = [project(p) for f in mesh.faces for p in f[:3]]
    limits = [(min(p[i] for p in points),max(p[i] for p in points)) for i in (0,1)]
    scale = min(1460/(limits[0][1]-limits[0][0]),790/(limits[1][1]-limits[1][0]))
    mid = [(lo+hi)/2 for lo,hi in limits]
    for face in mesh.faces:
        if sum(face[3][i]*view[i] for i in range(3)) <= 0:
            continue
        shade = .5+.5*max(0,sum(face[3][i]*(-.3,.88,.36)[i] for i in range(3)))
        color = [int(255*c*shade) for c in PALETTE[face[4]]]
        vertices = [(800+(project(p)[0]-mid[0])*scale,
                     530+(project(p)[1]-mid[1])*scale,project(p)[2]) for p in face[:3]]
        x0, x1 = max(0,int(min(p[0] for p in vertices))), min(width-1,int(max(p[0] for p in vertices))+1)
        y0, y1 = max(0,int(min(p[1] for p in vertices))), min(height-1,int(max(p[1] for p in vertices))+1)
        a,b,c = vertices
        denominator = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(denominator) < 1e-8 or x0 > x1 or y0 > y1:
            continue
        yy,xx = np.mgrid[y0:y1+1,x0:x1+1]
        u = ((b[1]-c[1])*(xx+.5-c[0])+(c[0]-b[0])*(yy+.5-c[1]))/denominator
        v = ((c[1]-a[1])*(xx+.5-c[0])+(a[0]-c[0])*(yy+.5-c[1]))/denominator
        w = 1-u-v
        z = u*a[2]+v*b[2]+w*c[2]
        target = depth[y0:y1+1,x0:x1+1]
        mask = (u>=0)&(v>=0)&(w>=0)&(z>target)
        target[mask] = z[mask]
        pixels[y0:y1+1,x0:x1+1][mask] = color
    image = Image.fromarray(pixels)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',30)
    small = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',21)
    draw.text((40,28),title,font=font,fill=(240,240,240))
    draw.text((40,78),'공개 외관 참고 / 비실측 근사 모델 / 실제 생성 메시 직접 투영',font=small,fill=(175,175,175))
    draw.text((40,990),f'{len(mesh.faces):,} triangles / 단위 m / 기존 지도와 자동 연결하지 않은 독립 에셋',font=small,fill=(190,190,190))
    image.save(path)
