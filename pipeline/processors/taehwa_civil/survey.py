"""기존 공개 수계와 DEM을 읽어 지리 좌표 및 표고 근거를 제공한다."""
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from shapely.geometry import LineString, shape, Polygon, Point, box
from shapely.ops import transform, unary_union, substring

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "godot_project/assets/generated/taehwa_civil"
STAGE = ROOT / "previews/taehwa_civil/project"


class Survey:
    def __init__(self):
        self.spec = json.loads((ROOT / "config/taehwa_civil.json").read_text(encoding="utf-8"))
        self.base = ROOT / "godot_project/assets/maps/ulsan_metro_80km"
        self.meta = json.loads((self.base / "map_meta.json").read_text(encoding="utf-8"))
        self.bbox = self.meta["bbox"]
        self.source = ROOT / "godot_project/assets/generated/railway/graded_heightmap_16bit.png"
        self.dem = np.asarray(Image.open(self.source)).astype(float)
        self.low, self.high = self.meta["min_elevation"], self.meta["max_elevation"]
        self.world_size = 80000
        self.source_hash = hashlib.sha256(self.source.read_bytes()).hexdigest()
        coordinates = json.loads((ROOT / "results/sources/taehwa_civil/centerline.json").read_text(encoding="utf-8"))["coordinates"]
        original = LineString([self.world(*p) for p in coordinates])
        policy = self.spec["river_policy"]
        start = original.project(self.project(PointProxy(policy["start_lon"], 35.562)))
        end = original.project(self.project(PointProxy(policy["end_lon"], 35.542)))
        self.line = substring(original, start, end)
        rivers = json.loads((self.base / "hydro/river.geojson").read_text(encoding="utf-8"))["features"]
        clip = self.line.buffer(650, cap_style=2)
        # 하천 중심선은 면이 아니다. 기존 수계 파일의 닫힌 중심선 다각형을 제외한다.
        selected = [self.project(shape(f["geometry"])) for f in rivers
                    if f['properties'].get('tags',{}).get('natural')=='water']
        selected = [p for p in selected if p.distance(self.line) < 18]
        # 태화강 하구는 기존 지도에서 해안선/해양 마스크로 분류된다.
        # 기존 해양 마스크를 회랑 안에서 벡터화한다. 원본 약 14m 격자 정밀도를 따른다.
        sea=np.asarray(Image.open(self.base/'hydro/sea_mask.png').convert('L'))
        n=sea.shape[0];xmin,zmin,xmax,zmax=clip.bounds
        left=max(0,int((xmin/80000+.5)*(n-1)));right=min(n,int((xmax/80000+.5)*(n-1))+2)
        top=max(0,int((zmin/80000+.5)*(n-1)));bottom=min(n,int((zmax/80000+.5)*(n-1))+2)
        strips=[]
        for y in range(top,bottom):
            row=np.pad((sea[y,left:right]>127).astype('int8'),(1,1))
            starts=np.where(np.diff(row)==1)[0]+left;ends=np.where(np.diff(row)==-1)[0]+left
            for start,end in zip(starts,ends):
                strips.append(box(((start-.5)/(n-1)-.5)*80000,((y-.5)/(n-1)-.5)*80000,
                                  ((end-.5)/(n-1)-.5)*80000,((y+.5)/(n-1)-.5)*80000))
        tidal=unary_union(strips).simplify(6,preserve_topology=True).intersection(clip)
        selected.append(tidal)
        mapped = unary_union(selected).intersection(clip).buffer(0)
        # 공개 수역 면이 없는 상류는 OSM 중심선에 가변 폭을 부여한다.
        # 폭은 보 축선/공개 영상에 근거한 시각화 추정이며 측량 경계와 구분한다.
        stations=np.linspace(0,self.line.length,math.ceil(self.line.length/70)+1)
        first_mapped=next((s for s in stations if mapped.covers(self.line.interpolate(s))),self.line.length)
        controls=[(self.line.project(Point(self.world(lon,lat))),width) for lon,lat,width in
                  [(129.113,35.562,32),(129.1428131,35.5527419,53),(129.18,35.547,40),
                   (129.214,35.576,45),(129.224,35.584,65),(129.238,35.581,75)]]
        controls.sort()
        strips=[]
        for s0,s1 in zip(stations,stations[1:]):
            if s0>first_mapped: break
            corners=[]
            for station,sign in [(s0,-1),(s1,-1),(s1,1),(s0,1)]:
                p=self.line.interpolate(station)
                a,b=self.line.interpolate(max(0,station-10)),self.line.interpolate(min(self.line.length,station+10))
                dx,dz=b.x-a.x,b.y-a.y;norm=math.hypot(dx,dz)
                width=float(np.interp(station,[c[0] for c in controls],[c[1] for c in controls]))
                corners.append((p.x-sign*dz/norm*width,p.y+sign*dx/norm*width))
            strips.append(Polygon(corners))
        self.river=unary_union([mapped,*strips]).buffer(0)
        self.boundary_status={'mapped_area_m2':mapped.area,'estimated_upper_width_length_m':float(first_mapped),
                              'estimated_upper_width_controls_half_m':controls}
        lakes = json.loads((self.base / "hydro/lake.geojson").read_text(encoding="utf-8"))["features"]
        self.basins = [self.project(shape(next(f for f in lakes if f["properties"]["osm_id"] == n)["geometry"]))
                       for n in (187657447, 187657448)]

    def world(self, lon, lat):
        b = self.bbox
        return ((lon-b["west"])/(b["east"]-b["west"])-.5)*self.world_size, ((b["north"]-lat)/(b["north"]-b["south"])-.5)*self.world_size

    def lonlat(self, x, z):
        b = self.bbox
        return b["west"]+(x/self.world_size+.5)*(b["east"]-b["west"]), b["north"]-(z/self.world_size+.5)*(b["north"]-b["south"])

    def project(self, geometry):
        return transform(self.world, geometry)

    def height(self, x, z):
        xx = np.clip((np.asarray(x)/self.world_size+.5)*(self.dem.shape[1]-1), 0, self.dem.shape[1]-1.001)
        yy = np.clip((np.asarray(z)/self.world_size+.5)*(self.dem.shape[0]-1), 0, self.dem.shape[0]-1.001)
        ix, iy = xx.astype(int), yy.astype(int)
        dx, dy = xx-ix, yy-iy
        v = (self.dem[iy,ix]*(1-dx)+self.dem[iy,ix+1]*dx)*(1-dy)+(self.dem[iy+1,ix]*(1-dx)+self.dem[iy+1,ix+1]*dx)*dy
        return self.low+v/65535*(self.high-self.low)


def PointProxy(x, y):
    from shapely.geometry import Point
    return Point(x, y)
