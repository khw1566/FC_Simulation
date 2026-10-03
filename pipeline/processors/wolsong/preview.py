"""생성 메시를 직접 투영하는 독립 경량 미리보기."""

from PIL import Image, ImageDraw, ImageFont
import numpy as np
from vessels.mesh import PALETTE


def render(mesh,path):
    image = Image.new('RGB',(1500,1000),(24,24,24))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',28)
    draw.text((40,25),'월성 원자력발전소 / 1~4호기 외관 에셋',font=font,fill=(235,235,235))
    def project(p):
        x,y,z = p
        return (.82*x-.57*z,-.32*x-.78*y-.46*z,-.44*x+.55*y-.68*z)
    points = [project(p) for f in mesh.faces for p in f[:3]]
    bounds = [(min(p[k] for p in points),max(p[k] for p in points)) for k in range(2)]
    scale = min(1360/(bounds[0][1]-bounds[0][0]),760/(bounds[1][1]-bounds[1][0]))
    mid = [(a+b)/2 for a,b in bounds]
    pixels = np.array(image)
    depth = np.full((1000,1500),-np.inf)
    for face in mesh.faces:
        normal = face[3]
        if sum(normal[k]*(-.44,.55,-.68)[k] for k in range(3)) <= 0:
            continue
        shade = .48+.52*max(0,sum(normal[k]*(-.4,.85,-.35)[k] for k in range(3)))
        color = tuple(int(255*c*shade) for c in PALETTE[face[4]])
        vertices = [(750+(project(p)[0]-mid[0])*scale,
                     490+(project(p)[1]-mid[1])*scale,project(p)[2]) for p in face[:3]]
        x0 = max(0,int(min(p[0] for p in vertices)))
        x1 = min(1499,int(max(p[0] for p in vertices))+1)
        y0 = max(0,int(min(p[1] for p in vertices)))
        y1 = min(999,int(max(p[1] for p in vertices))+1)
        a,b,c = vertices
        denominator = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(denominator) < 1e-8:
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
    draw.text((40,925),'공개 외관 참고 · 비실측 모델 · GLB 메시 직접 투영 · 단위 m',font=font,fill=(190,190,190))
    image.save(path)
