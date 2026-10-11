"""생성한 실제 삼각형의 측면과 사시도를 확인용 PNG로 저장한다."""
from PIL import Image, ImageDraw, ImageFont
from .models import PALETTE


def render(items,path):
    image=Image.new("RGB",(1800,90+232*len(items)),(24,24,24))
    draw=ImageDraw.Draw(image)
    font=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",25)
    small=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",18)
    draw.text((30,20),"태화강 교량 / 조사 기반 1차 초안 · 지도 미적용",font=font,fill="white")
    for row,(spec,mesh) in enumerate(items):
        y0=80+row*232
        draw.text((30,y0),spec["label"],font=font,fill="white")
        draw.text((500,y0),f'{spec["length"]}m / 폭 {spec["widths"]}m / {len(mesh.faces):,} triangles',font=small,fill=(190,190,190))
        for col,oblique in enumerate((False,True)):
            def project(p):
                x,y,z=p
                return (z+.7*x,-y+.3*x+.065*z,x+.35*y-.1*z) if oblique else (z,-y,x)
            points=[project(p) for f in mesh.faces for p in f[:3]]
            bounds=[(min(p[k] for p in points),max(p[k] for p in points)) for k in (0,1)]
            scale=min(820/(bounds[0][1]-bounds[0][0]),160/(bounds[1][1]-bounds[1][0]))
            middle=[sum(b)/2 for b in bounds]
            for face in sorted(mesh.faces,key=lambda f:sum(project(p)[2] for p in f[:3])):
                color=PALETTE[face[4]]
                shade=.65+.35*abs(face[3][1])
                xy=[(450+col*900+(project(p)[0]-middle[0])*scale,y0+120+(project(p)[1]-middle[1])*scale) for p in face[:3]]
                draw.polygon(xy,fill=tuple(int(255*c*shade) for c in color))
        draw.line((20,y0+215,1780,y0+215),fill=(70,70,70))
    image.save(path)
