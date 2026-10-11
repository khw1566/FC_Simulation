"""원본을 읽기만 하여 GLB·방향·고도 근거와 국소 배치 프리뷰를 만든다."""
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image,ImageDraw,ImageFont
from shapely.geometry import shape,Point

if __package__ in (None, ""):
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    __package__="ulsan_dams"
from .generate import ROOT,OUT,STAGE
from custom_lowpoly.glb import inspect,export
from vessels.mesh import VesselMesh


def sample(image,bbox,lon,lat):
    x=(lon-bbox["west"])/(bbox["east"]-bbox["west"])*(image.width-1)
    y=(bbox["north"]-lat)/(bbox["north"]-bbox["south"])*(image.height-1)
    x=max(0,min(image.width-1.00001,x)); y=max(0,min(image.height-1.00001,y))
    ix,iy=int(x),int(y)
    dx,dy=x-ix,y-iy
    a=image.getpixel((ix,iy))*(1-dx)+image.getpixel((ix+1,iy))*dx
    b=image.getpixel((ix,iy+1))*(1-dx)+image.getpixel((ix+1,iy+1))*dx
    return a*(1-dy)+b*dy


def main():
    catalog=json.loads((OUT/"catalog.json").read_text(encoding="utf-8"))
    base=ROOT/"godot_project/assets/maps/ulsan_metro_80km"
    meta=json.loads((base/"map_meta.json").read_text(encoding="utf-8"))
    source=ROOT/"godot_project/assets/generated/railway/graded_heightmap_16bit.png"
    if not source.exists():
        source=ROOT/"godot_project"/meta["assets"]["heightmap"].removeprefix("res://")
    before=hashlib.sha256(source.read_bytes()).hexdigest()
    dem=Image.open(source)
    lakes=json.loads((base/"hydro/lake.geojson").read_text(encoding="utf-8"))["features"]
    checks=[]
    low,high=meta["min_elevation"],meta["max_elevation"]
    height=lambda lon,lat: low+sample(dem,meta["bbox"],lon,lat)/65535*(high-low)
    for spec in catalog["models"]:
        for lod in spec["lods"]:
            path=OUT/Path(lod["file_path"]).name
            assert inspect(path)["triangles"]==lod["triangles"]
            assert hashlib.sha256(path.read_bytes()).hexdigest()==lod["sha256"]
        lake=shape(next(f for f in lakes if f["properties"]["osm_id"]==spec["reservoir_osm_id"])["geometry"])
        lon,lat=spec["anchor"]["lon"],spec["anchor"]["lat"]
        east=111320*math.cos(math.radians(lat)); north=111320
        yaw=spec["axis_yaw_rad"]
        def geolocation(x,z):
            return lon+(math.cos(yaw)*x+math.sin(yaw)*z)/east,lat-(-math.sin(yaw)*x+math.cos(yaw)*z)/north
        upstream=Point(geolocation(0,-100))
        downstream=Point(geolocation(0,100))
        assert lake.distance(upstream)<lake.distance(downstream),spec["id"]
        a,b=spec["axis_lonlat"]
        heights=sorted(height(a[0]+(b[0]-a[0])*t/20,a[1]+(b[1]-a[1])*t/20) for t in range(2,19))
        crest=heights[math.floor((len(heights)-1)*.9)]+.35
        patch=VesselMesh()
        size=max(700,spec["official_length_m"]*2)
        grid=np.linspace(-size/2,size/2,49)
        values=[[height(*geolocation(x,z))-crest for x in grid] for z in grid]
        (STAGE/f"{spec['id']}_terrain.json").write_text(json.dumps({"min":-size/2,"step":size/48,"values":values}),encoding="utf-8")
        def vertex(x,z):
            p=geolocation(x,z)
            return (x,height(*p)-crest,z)
        for i in range(len(grid)-1):
            for j in range(len(grid)-1):
                x0,x1=grid[i:i+2]; z0,z1=grid[j:j+2]
                center=Point(geolocation((x0+x1)/2,(z0+z1)/2))
                material="water" if lake.contains(center) else "ground"
                patch.quad(vertex(x0,z1),vertex(x1,z1),vertex(x1,z0),vertex(x0,z0),material)
        export(patch,STAGE/f"{spec['id']}_terrain.glb",spec["id"]+"_terrain",{"ground":(.25,.30,.22),"water":(.10,.26,.31)})
        checks.append({"id":spec["id"],"name_ko":spec["name_ko"],"upstream_orientation":True,
                       "axis_status":spec["axis_status"],"axis_length_m":spec["axis_length_m"],
                       "official_length_m":spec["official_length_m"],"crest_dem_estimate_m":round(crest,3),
                       "interior_dem_range_m":[round(heights[0],3),round(heights[-1],3)]})
    assert before==hashlib.sha256(source.read_bytes()).hexdigest()
    report={"passed":True,"model_count":5,"glb_count":10,"terrain_source":source.relative_to(ROOT).as_posix(),
            "terrain_source_sha256":before,"terrain_source_unchanged":True,"resolution":[dem.width,dem.height],
            "height_note":"기준 품질 래스터 표본. 실행 중 품질별 래스터·철도 보정과 실제 청크 표면은 별도.","checks":checks}
    (ROOT/"results/261011_UlsanDamsVerification.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False))


def montage():
    catalog=json.loads((OUT/"catalog.json").read_text(encoding="utf-8"))
    atlas=Image.new("RGB",(1650,780),"white")
    font=ImageFont.truetype("C:/Windows/Fonts/malgun.ttf",22)
    for index,spec in enumerate(catalog["models"]):
        image=Image.open(STAGE/f"{spec['id']}_placement_preview.png").resize((550,340))
        x,y=(index%3)*550,(index//3)*390
        atlas.paste(image,(x,y+40))
        ImageDraw.Draw(atlas).text((x+15,y+8),f"{spec['name_ko']} ({spec['official_length_m']}m / {spec['official_height_m']}m)",font=font,fill="black")
    ImageDraw.Draw(atlas).text((1115,450),"기존 DEM 위 국소 배치 프리뷰\n공식 제원 + 추정 단면·DEM 표고\n전체 지도 실행 없음",font=font,fill="black",spacing=12)
    atlas.save(ROOT/"results/261011_UlsanDamsPlacementPreview.png")


if __name__=="__main__":
    montage() if "--montage" in sys.argv else main()
