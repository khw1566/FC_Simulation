"""전체 조사 격자의 선분 길이 집계와 흑백 SVG 비교도."""
import csv
import json
import math
from collections import Counter
from pathlib import Path


def summarize(roads, config):
    size = config["world_size_meters"]
    b = config["bbox"]
    ny = math.ceil((b["north"]-b["south"])/.025)
    nx = math.ceil((b["east"]-b["west"])/.025)
    dx, dz = size/nx, size/ny
    cells = [0.0]*(nx*ny)
    lengths, counts = Counter(), Counter()
    outside = 0
    for road in roads:
        kind = road["type"]
        counts[kind] += 1
        if any(abs(p[0])>30000 or abs(p[2])>30000 for p in road["points"]):
            outside += 1
        for a, c in zip(road["points"], road["points"][1:]):
            x1, z1, x2, z2 = a[0]+size/2, a[2]+size/2, c[0]+size/2, c[2]+size/2
            length = math.hypot(x2-x1,z2-z1)
            lengths[kind] += length
            cuts = [0.,1.]
            for v1,v2,step,n in ((x1,x2,dx,nx),(z1,z2,dz,ny)):
                if abs(v2-v1) < 1e-9:
                    continue
                for k in range(max(1,math.floor(min(v1,v2)/step)+1), min(n,math.ceil(max(v1,v2)/step))):
                    cuts.append((k*step-v1)/(v2-v1))
            cuts = sorted(set(cuts))
            for start,end in zip(cuts,cuts[1:]):
                t = (start+end)/2
                ix, iy = int((x1+t*(x2-x1))/dx), int((z1+t*(z2-z1))/dz)
                if 0 <= ix < nx and 0 <= iy < ny:
                    cells[iy*nx+ix] += length*(end-start)
    return {"road_count":len(roads),"types":dict(counts),
            "length_km_by_type":{k:round(v/1000,3) for k,v in lengths.items()},
            "total_length_km":round(sum(lengths.values())/1000,3),
            "roads_touching_outer_10km":outside,"grid":[nx,ny],
            "cells_with_roads":sum(v>0 for v in cells), "cell_length_m":cells}


def write(folder, before, after):
    folder = Path(folder)
    folder.mkdir(parents=True,exist_ok=True)
    (folder/"coverage.json").write_text(json.dumps({"before":before,"after":after},ensure_ascii=False,indent=2),encoding="utf-8")
    nx,ny = after["grid"]
    with (folder/"coverage.csv").open("w",encoding="utf-8-sig",newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["cell_id","before_length_m","after_length_m","status"])
        for i,value in enumerate(after["cell_length_m"]):
            writer.writerow([f"ulsan80_y{i//nx:02}_x{i%nx:02}",round(before["cell_length_m"][i],2),round(value,2),"roads_present" if value else "empty_source_review"])
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="550" viewBox="0 0 1120 550">',
             '<rect width="1120" height="550" fill="white"/>']
    for offset,data,label in ((20,before,"Before"),(580,after,"After")):
        parts.append(f'<text x="{offset}" y="25" font-family="sans-serif" font-size="18">{label}: {data["road_count"]} roads</text>')
        for i,value in enumerate(data["cell_length_m"]):
            shade = 245 if value == 0 else int(215-180*min(1,math.log1p(value)/math.log(60000)))
            parts.append(f'<rect x="{offset+i%nx*14}" y="{40+i//nx*16}" width="14" height="16" fill="rgb({shade},{shade},{shade})" stroke="#aaa" stroke-width=".3"/>')
    parts.append('<text x="20" y="535" font-family="sans-serif" font-size="13">Darker = more source road length. Empty cells are not automatically missing roads.</text></svg>')
    (folder/"coverage.svg").write_text("\n".join(parts),encoding="utf-8")


def land_review():
    # 무도로 셀을 수계 마스크와 대조하되, 육상 셀을 임의의 도로로 채우지 않는다.
    from PIL import Image
    import hashlib
    root = Path(__file__).resolve().parents[3]
    folder = root/"results/ulsan_80km_roads"
    coverage = json.loads((folder/"coverage.json").read_text(encoding="utf-8"))
    meta = json.loads((root/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8"))
    water = root/"godot_project"/meta["assets"]["watermask"].removeprefix("res://")
    nx,ny = coverage["after"]["grid"]
    with Image.open(water) as image:
        reduced = image.convert("L").resize((nx,ny),Image.Resampling.BOX)
        fractions = [1-reduced.getpixel((x,y))/255 for y in range(ny) for x in range(nx)]
    review, sea = [], 0
    for i,length in enumerate(coverage["after"]["cell_length_m"]):
        if length > 0:
            continue
        if fractions[i] < .05:
            sea += 1
        else:
            review.append({"cell_id":f"ulsan80_y{i//nx:02}_x{i%nx:02}","estimated_land_fraction":round(fractions[i],3),
                           "status":"source_has_no_road_review","basis":"full_bbox_query_and_water_mask"})
    with water.open("rb") as stream:
        water_hash = hashlib.file_digest(stream,"sha256").hexdigest()
    result = {"empty_cells":nx*ny-coverage["after"]["cells_with_roads"],
              "mostly_water_empty_cells":sea,"land_empty_cells_for_review":review,
              "water_mask_sha256":water_hash,"land_fraction_is_mask_estimate":True,
              "note_ko":"전 범위 OSM 응답에 도로가 없는 셀이다. 현실의 누락 여부는 별도 자료 대조가 필요하며 도로를 추정 생성하지 않았다."}
    (folder/"empty_cell_review.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"empty_cells":result["empty_cells"],"mostly_water":sea,"land_review":len(review)}),flush=True)


def chart():
    from PIL import Image,ImageDraw,ImageFont
    root=Path(__file__).resolve().parents[3]
    folder=root/"results/ulsan_80km_roads"
    coverage=json.loads((folder/"coverage.json").read_text(encoding="utf-8"))
    image=Image.new("RGB",(1200,660),"white")
    draw=ImageDraw.Draw(image)
    font=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",22)
    small=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",16)
    draw.text((25,15),"울산 80km 전체 도로 분포 비교",font=font,fill="black")
    for x,key,label in ((25,"before","기존"),(625,"after","보완 후")):
        value=coverage[key]
        nx,ny=value["grid"]
        draw.text((x,60),f'{label}: {value["road_count"]:,}개 / 도로 포함 {value["cells_with_roads"]}셀',font=small,fill="black")
        for i,length in enumerate(value["cell_length_m"]):
            shade=245 if length==0 else int(215-180*min(1,math.log1p(length)/math.log(60000)))
            px,py=x+i%nx*15,100+i//nx*16
            draw.rectangle((px,py,px+15,py+16),fill=(shade,shade,shade),outline="#aaaaaa",width=1)
    draw.text((25,590),"북쪽 위 / 서쪽 왼쪽. 진할수록 원본 도로 길이가 많음. 흰 구역은 자동으로 누락을 뜻하지 않음.",font=small,fill="black")
    draw.text((25,620),"전체 1,044셀 조사. OSM 원본 기준이며 전체 맵 실행 또는 현실 도로 전수 검증 결과는 아님.",font=small,fill="black")
    image.save(folder/"coverage.png")


if __name__=="__main__":
    land_review()
    chart()
