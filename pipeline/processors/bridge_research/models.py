"""외부 텍스처 없는 교량 초안의 기하 생성만 담당한다."""
from taehwagang.geometry import StationMesh

PALETTE = {"concrete":(.63,.63,.63), "deck":(.23,.23,.23),
           "steel":(.48,.48,.48), "cable":(.73,.73,.73), "wood":(.48,.43,.36)}


def build(spec):
    mesh = StationMesh()
    length = spec["length"]
    deck = spec.get("deck", 0)
    total = sum(spec["widths"]) + (len(spec["widths"])-1)*.8
    cursor = -total/2
    for index, width in enumerate(spec["widths"]):
        x = cursor + width/2
        cursor += width+.8
        kind = spec["kind"]
        thickness = 2.4 if kind == "suspension" else 1.2
        mesh.box((x,deck-thickness/2,0),(width,thickness,length),
                 "wood" if kind == "pedestrian" else "deck")
        for sign in (-1,1):
            side = x+sign*(width/2-.18)
            mesh.box((side,deck+.5,0),(.25,1,length),"concrete")
            mesh.box((side,deck+1.05,0),(.12,.10,length),"steel")
        if kind == "suspension":
            suspension(mesh,spec)
            continue
        girder = kind
        if kind == "mixed_girder":
            girder = "i_girder" if index == 0 else "box_girder"
        if girder == "i_girder":
            for j in range(5):
                gx = x-width*.4+j*width*.2
                mesh.box((gx,-2.1,0),(.35,1.8,length),"concrete")
                for y in (-1.25,-2.95):
                    mesh.box((gx,y,0),(1.1,.22,length),"concrete")
        elif girder == "box_girder":
            for sign in (-1,1):
                mesh.box((x+sign*width*.24,-2.1,0),(width*.32,2,length),"concrete")
        # 교각 간격과 기초 깊이는 실측값이 아닌 확인용 초안이다.
        count = max(3,round(length/40))
        spans=spec.get("spans",[length/count]*count)
        positions=[]
        distance=-length/2
        for span in spans[:-1]:
            distance+=span
            positions.append(distance)
        for z in positions:
            mesh.box((x,-3.6,z),(width*.85,1,2.4),"concrete")
            for sign in ((0,) if spec.get("pier_kind")=="T" else (-1,1)):
                mesh.box((x+sign*width*.25,-7.0,z),(1.8,6,1.8),"concrete")
    return mesh


def suspension(mesh,spec):
    span, top, deck = spec["span"],spec["tower"],spec["deck"]
    width, length = spec["widths"][0],spec["length"]
    side = width*.57
    # U형 주탑의 상부 개구를 남긴다. 세부 단면은 사진 대조 전 근사.
    for z in (-span/2,span/2):
        for sign in (-1,1):
            mesh.beam((sign*(side+3),0,z),(sign*side,top,z),6,7,"concrete")
        for y in (deck-7,top-30):
            mesh.box((0,y,z),(side*2,4,7),"concrete")
    for sign in (-1,1):
        x = sign*side
        def cable(z):
            return (x,deck+20+(top-deck-20)*(2*z/span)**2,z)
        for i in range(81):
            z = -span/2+span*i/80
            if i < 80:
                mesh.cylinder(cable(z),cable(z+span/80),.38,"cable",6)
            if 0 < i < 80:
                mesh.cylinder((x,deck,z),cable(z),.08,"cable",4)
        for end in (-1,1):
            anchor = end*length/2
            mesh.cylinder((x,top,end*span/2),(x,deck+5,anchor),.38,"cable",6)
            mesh.box((x,deck+1,anchor),(5,8,8),"concrete")
    # 접속부가 바닥으로 꺾이는 기존 프리뷰를 피한다. 실제 종단은 추후 대조.
    for end in (-1,1):
        for fraction in (.68,.84):
            z = end*length*fraction/2
            mesh.box((0,deck/2,z),(width*.65,deck,3),"concrete")
