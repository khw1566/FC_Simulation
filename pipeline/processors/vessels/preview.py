"""실제 생성 메시를 직교 투영하여 가벼운 미리보기를 만든다."""

import math
from PIL import Image, ImageDraw, ImageFont
from .mesh import PALETTE


def render_preview(vessels, path):
    image = Image.new("RGB",(1800,1100),(22,25,29))
    draw = ImageDraw.Draw(image)
    font_path = "C:/Windows/Fonts/malgun.ttf"
    title_font = ImageFont.truetype(font_path,30)
    label_font = ImageFont.truetype(font_path,23)
    small_font = ImageFont.truetype(font_path,17)
    draw.text((40,24),"해상 선박 에셋 / 6종",font=title_font,fill=(235,237,238))
    draw.text((40,70),"실제 GLB 메시 미리보기 · 각 칸 독립 축척 · 단위 m · 선수 -Z",font=small_font,fill=(155,165,175))
    for index,(kind,label,length,beam,mesh) in enumerate(vessels):
        cx = 300+(index%3)*600
        cy = 320+(index//3)*470
        draw.rounded_rectangle((cx-280,cy-205,cx+280,cy+235),radius=14,
                               fill=(30,35,40),outline=(58,65,72))
        def project(p):
            x,y,z = p
            return (.82*x-.57*z, -.32*x-.78*y-.46*z, -.44*x+.55*y-.68*z)
        points = [project(p) for f in mesh.faces for p in f[:3]]
        bounds = [(min(p[k] for p in points),max(p[k] for p in points)) for k in range(2)]
        scale = min(490/(bounds[0][1]-bounds[0][0]),300/(bounds[1][1]-bounds[1][0]))
        mid = [(lo+hi)/2 for lo,hi in bounds]
        faces = sorted(mesh.faces,key=lambda f:sum(project(p)[2] for p in f[:3])/3)
        light = (-.4,.85,-.35)
        for face in faces:
            # 투영의 관찰 방향과 법선을 이용해 뒷면을 제거한다.
            normal = face[3]
            if normal[0]*-.44+normal[1]*.55+normal[2]*-.68 <= 0:
                continue
            shade = .48+.52*max(0,sum(normal[k]*light[k] for k in range(3)))
            color = tuple(int(255*c*shade) for c in PALETTE[face[4]])
            xy = [(cx+(project(p)[0]-mid[0])*scale,
                   cy-20+(project(p)[1]-mid[1])*scale) for p in face[:3]]
            draw.polygon(xy,fill=color)
        draw.text((cx-250,cy+162),label,font=label_font,fill=(230,233,236))
        draw.text((cx-250,cy+198),f"{length:g} × {beam:g} m   /   {len(mesh.faces):,} triangles",
                  font=small_font,fill=(150,161,171))
    image.save(path)
