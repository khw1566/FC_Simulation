"""원본 수역·도로·DEM을 읽어 댐 축선 검토용 지도를 기록한다."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
LAKES = {"sayeon": 37220214, "daegok": 382710949, "daeam": 37220310,
         "seonam": 998164001, "hoeya": 156408222}


def main():
    base = ROOT / "godot_project/assets/maps/ulsan_metro_80km"
    lakes = json.loads((base / "hydro/lake.geojson").read_text(encoding="utf-8"))["features"]
    roads = json.loads((ROOT / "data/raw/ulsan_metro_80km/highways/full_80km.json").read_text(encoding="utf-8"))["elements"]
    dams = json.loads((ROOT / "results/sources/ulsan_dams/osm_dams.json").read_text(encoding="utf-8"))["elements"]
    meta = json.loads((base / "map_meta.json").read_text(encoding="utf-8"))
    dem = Image.open(base / "hydro/coastal_heightmap_16bit.png")
    b = meta["bbox"]
    canvas = Image.new("RGB", (1800, 1200), "white")
    for index, (key, osm) in enumerate(LAKES.items()):
        feature = next(f for f in lakes if f["properties"]["osm_id"] == osm)
        ring = np.array(feature["geometry"]["coordinates"][0][0])
        west, south = ring.min(axis=0) - .003
        east, north = ring.max(axis=0) + .003
        px = lambda lon: (lon-b["west"])/(b["east"]-b["west"])*dem.width
        py = lambda lat: (b["north"]-lat)/(b["north"]-b["south"])*dem.height
        img = np.asarray(dem.crop((int(px(west)), int(py(north)), int(px(east)), int(py(south)))))
        heights = -30 + img.astype(float)/65535*1330
        gray = np.uint8(np.clip(240-heights*.7, 50, 240))
        panel = Image.fromarray(gray).convert("RGB").resize((580,540))
        draw = ImageDraw.Draw(panel)
        point = lambda lon,lat: ((lon-west)/(east-west)*580,(north-lat)/(north-south)*540)
        draw.polygon([point(*p) for p in ring], fill="#61acc0")
        for road in roads:
            bounds = road.get("bounds", {})
            if not bounds or bounds["maxlon"] < west or bounds["minlon"] > east or bounds["maxlat"] < south or bounds["minlat"] > north:
                continue
            points = road.get("geometry", [])
            if len(points)>1:
                draw.line([point(p["lon"],p["lat"]) for p in points], fill="black", width=1)
        for dam in dams:
            points = dam["geometry"]
            if west < points[0]["lon"] < east and south < points[0]["lat"] < north:
                draw.line([point(p["lon"],p["lat"]) for p in points], fill="red", width=3)
                draw.text(point(points[0]["lon"],points[0]["lat"]),str(dam["id"]),fill="red")
        x,y=(index%3)*600,(index//3)*600
        canvas.paste(panel,(x+10,y+45))
        labels=ImageDraw.Draw(canvas)
        labels.text((x+10,y+5),f"{key} / reservoir way {osm}",fill="black")
        labels.text((x+10,y+22),f"W {west:.7f} E {east:.7f} S {south:.7f} N {north:.7f}",fill="black")
    canvas.save(ROOT / "results/sources/ulsan_dams/axis_research.png")
    print("댐 축선 검토 지도 기록 완료")


if __name__ == "__main__":
    main()
