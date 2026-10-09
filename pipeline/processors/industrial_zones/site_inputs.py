"""현 지도 지형·수계·기존 시설의 공단 배치 제외 영역."""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import Point, Polygon, LineString, box
from shapely.ops import unary_union
from shapely.strtree import STRtree


class IndustrialSiteInputs:
    def __init__(self, root, config):
        self.root, self.config = root, config
        self.meta = self.read(root/f"godot_project/assets/maps/{config['map_id']}/map_meta.json")
        self.size = self.meta["world_size_meters"]
        self.bbox = self.meta["bbox"]
        self.resolution = int(config["resolution"])
        self.cell = self.size/(self.resolution-1)
        def image(key):
            return root/"godot_project"/self.meta["assets"][key].removeprefix("res://")
        with Image.open(image("heightmap")) as source:
            self.height = np.asarray(source).astype(np.float32)/65535*(self.meta["max_elevation"]-self.meta["min_elevation"])+self.meta["min_elevation"]
        with Image.open(image("watermask")) as source:
            water = source.convert("L").resize((self.resolution,self.resolution),Image.Resampling.BILINEAR).point(lambda p:255 if p>=64 else 0)
        radius = math.ceil(config["water_buffer_m"]/self.cell)+1
        self.water = water.filter(ImageFilter.MaxFilter(radius*2+1))
        reduced = Image.fromarray(self.height).resize((self.resolution,self.resolution),Image.Resampling.BILINEAR)
        heights = np.asarray(reduced)
        dy, dx = np.gradient(heights,self.cell)
        steep = np.hypot(dx,dy)>math.tan(math.radians(config.get("max_slope_degrees",8)))
        bad = (np.asarray(self.water)>0)|steep|(heights<0.8)
        self.raster = Image.fromarray((bad*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
        harbor_config = self.read(root/"config/vessel_traffic.json")
        self.anchors = [h for h in harbor_config["harbors"] if h["id"] in ("ulsan_main","onsan")]
        # 항구 기준점 주변과 확정 구역 외곽 상자 주변의 시설만 읽는다.
        windows = []
        for h in self.anchors:
            c = self.project([h["lon"],h["lat"]])
            windows.append((c[0]-5000,c[1]-5000,c[0]+5000,c[1]+5000))
        regions = self.read(root/config["regions_path"])
        for feature in regions.get("features",[]):
            rings = feature["geometry"]["coordinates"]
            outer = [rings[0]] if feature["geometry"]["type"]=="Polygon" else [poly[0] for poly in rings]
            points = [self.project(p) for ring in outer for p in ring]
            xs,zs = [p[0] for p in points],[p[1] for p in points]
            windows.append((min(xs)-1000,min(zs)-1000,max(xs)+1000,max(zs)+1000))
        vectors = self.read(image("buildings_roads"))
        def near(p):
            return any(w[0]<=p[0]<=w[2] and w[1]<=p[-1]<=w[3] for w in windows)
        protected, self.roads, self.buildings, self.building_info = [], [], [], []
        for building in vectors["buildings"]:
            if not near(building["center"]):
                continue
            polygon = Polygon(building["polygon"])
            if polygon.is_valid and not polygon.is_empty:
                # 기존 건물은 별도로 보관해 대체 구역에서는 보호하지 않을 수 있게 한다.
                self.buildings.append(polygon.buffer(4))
                # 블록 용도 판정에 쓰는 원래 형상과 이름·높이.
                self.building_info.append({"polygon": polygon, "name": str(building.get("name", "")),
                                           "height": float(building.get("height", 0.0))})
        for road in vectors["roads"]:
            if len(road["points"])<2 or not any(near(p) for p in road["points"]):
                continue
            line = LineString([(p[0],p[2]) for p in road["points"]])
            spec = {"id":road["id"],"line":line,"width":max(3,float(road.get("width",8)))}
            if road.get("bridge") or road.get("tunnel") or road.get("type") in ("motorway","motorway_link"):
                protected.append(line.buffer(spec["width"]/2+15))
            else:
                self.roads.append(spec)
        alignment = self.read(root/"godot_project/assets/generated/railway/alignment.json")
        for track in alignment["tracks"]:
            ps = track["points"]
            if len(ps)>1 and any(near(p) for p in ps):
                protected.append(LineString([(p[0],p[2]) for p in ps]).buffer(35))
        heritage = self.read(root/"config/ulsan_heritage_models.json")
        for landmark in heritage["landmarks"]:
            anchor = landmark["anchor"]
            protected.append(Point(self.project([anchor["lon"],anchor["lat"]])).buffer(300))
        airport = self.read(root/"godot_project/assets/generated/airport/placement.json")
        thresholds = airport["airfield"]
        ends = [self.project([thresholds[k]["lon"],thresholds[k]["lat"]]) for k in ("threshold_18","threshold_36")]
        protected.append(LineString(ends).buffer(550))
        self.protected = protected
        self.protected_tree = STRtree(protected)
        self.building_tree = STRtree(self.buildings)
        self.road_tree = STRtree([r["line"] for r in self.roads])

    @staticmethod
    def read(path):
        return json.loads(Path(path).read_text(encoding="utf-8-sig"))

    def project(self, p):
        return ((p[0]-self.bbox["west"])/(self.bbox["east"]-self.bbox["west"])*self.size-self.size/2,
                (self.bbox["north"]-p[1])/(self.bbox["north"]-self.bbox["south"])*self.size-self.size/2)

    def geographic(self, p):
        return [self.bbox["west"]+(p[0]/self.size+0.5)*(self.bbox["east"]-self.bbox["west"]),
                self.bbox["north"]-(p[1]/self.size+0.5)*(self.bbox["north"]-self.bbox["south"])]

    def sample(self, x, z):
        px = np.clip((x/self.size+0.5)*(self.height.shape[1]-1),0,self.height.shape[1]-1)
        py = np.clip((z/self.size+0.5)*(self.height.shape[0]-1),0,self.height.shape[0]-1)
        ix, iy = int(px), int(py)
        ix1,iy1 = min(ix+1,self.height.shape[1]-1),min(iy+1,self.height.shape[0]-1)
        return float((self.height[iy,ix]*(1-(px-ix))+self.height[iy,ix1]*(px-ix))*(1-(py-iy))+
                     (self.height[iy1,ix]*(1-(px-ix))+self.height[iy1,ix1]*(px-ix))*(py-iy))

    def safe_geometry(self, region, include_roads=False, include_buildings=True):
        bounds = region.bounds
        x0 = max(0,math.floor((bounds[0]/self.size+0.5)*(self.resolution-1))-1)
        y0 = max(0,math.floor((bounds[1]/self.size+0.5)*(self.resolution-1))-1)
        x1 = min(self.resolution,math.ceil((bounds[2]/self.size+0.5)*(self.resolution-1))+2)
        y1 = min(self.resolution,math.ceil((bounds[3]/self.size+0.5)*(self.resolution-1))+2)
        patch = np.asarray(self.raster)[y0:y1,x0:x1]>0
        blocked = []
        for y,row in enumerate(patch):
            indexes = np.flatnonzero(row)
            if not len(indexes):
                continue
            starts = np.r_[0,np.flatnonzero(np.diff(indexes)>1)+1]
            ends = np.r_[starts[1:]-1,len(indexes)-1]
            for start,end in zip(starts,ends):
                wx = (indexes[start]+x0)/(self.resolution-1)*self.size-self.size/2
                wz = (y+y0)/(self.resolution-1)*self.size-self.size/2
                width = (indexes[end]-indexes[start]+1)*self.cell
                blocked.append(box(wx-self.cell/2,wz-self.cell/2,wx+width-self.cell/2,wz+self.cell/2))
        indexes = self.protected_tree.query(region)
        blocked.extend(self.protected[int(i)].intersection(region) for i in indexes)
        if include_buildings:
            blocked.extend(self.buildings[int(i)].intersection(region) for i in self.building_tree.query(region))
        if include_roads:
            for i in self.road_tree.query(region):
                road = self.roads[int(i)]
                blocked.append(road["line"].buffer(road["width"]/2+5))
        return region.difference(unary_union(blocked)) if blocked else region

    def rasterize(self, geometry, image=None):
        image = image if image is not None else Image.new("L",(self.resolution,self.resolution))
        draw = ImageDraw.Draw(image)
        def pixel(p):
            return ((p[0]/self.size+0.5)*(self.resolution-1),(p[1]/self.size+0.5)*(self.resolution-1))
        polygons = [geometry] if geometry.geom_type=="Polygon" else getattr(geometry,"geoms",[])
        for polygon in polygons:
            if polygon.geom_type!="Polygon":
                continue
            draw.polygon([pixel(p) for p in polygon.exterior.coords],fill=255)
            for ring in polygon.interiors:
                draw.polygon([pixel(p) for p in ring.coords],fill=0)
        return image
