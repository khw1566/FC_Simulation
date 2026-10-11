"""유향·완만한 수면 종단과 별도 하상 메시/국소 높이 패치를 생성한다."""
import json
import math
import struct
import zlib
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import Point, box, mapping
from shapely.ops import unary_union, transform
from shapely import constrained_delaunay_triangles

from .survey import OUT, STAGE


class Hydro:
    def __init__(self, survey):
        self.survey = survey
        self.line = survey.line
        policy = survey.spec["river_policy"]
        self.stations = np.linspace(0, self.line.length, math.ceil(self.line.length/policy["sample_step_m"])+1)
        raw = np.array([survey.height(p.x, p.y) for p in [self.line.interpolate(s) for s in self.stations]])
        # 강 중앙 DEM의 짧은 잡음을 줄이고 역경사를 제거한다. 실측 수위는 아니다.
        smoothed = np.array([np.percentile(raw[max(0,i-2):i+3], 35) for i in range(len(raw))])+.55
        self.levels = np.maximum(policy["minimum_level_m"], np.minimum.accumulate(smoothed))
        self.weir = Point(survey.world(129.1428131, 35.5527419))
        self.coverage = unary_union([survey.river, *survey.basins])
        self.ground_coverage = self.coverage.buffer(18)

    @lru_cache(maxsize=100000)
    def shore_vertex(self,x,z):
        p=Point(x,z)
        basin=min(range(len(self.survey.basins)),key=lambda i:self.survey.basins[i].distance(p))
        if self.survey.basins[basin].distance(p)>self.survey.river.distance(p):basin=-1
        v=list(self.vertex(x,z,basin)); distance=self.coverage.distance(p)
        t=min(1.,distance/18);t=t*t*(3-2*t)
        v[1]=(v[1]-.12)*(1-t)+float(self.survey.height(x,z))*t
        v[5]=0
        return v

    @lru_cache(maxsize=200000)
    def vertex(self, x, z, basin=-1):
        p = Point(x, z)
        if basin >= 0:
            depth = .15+1.6*min(1., self.survey.basins[basin].boundary.distance(p)/8)
            return [x, .6, z, x, z, depth, min(1.,self.survey.basins[basin].boundary.distance(p)/14), 0.]
        s = self.line.project(p)
        center = self.line.interpolate(s)
        a, b = self.line.interpolate(max(0,s-10)), self.line.interpolate(min(self.line.length,s+10))
        dx, dz = b.x-a.x, b.y-a.y
        norm = max(math.hypot(dx,dz),.001)
        cross = (x-center.x)*(-dz/norm)+(z-center.y)*(dx/norm)
        edge = self.survey.river.boundary.distance(p)
        depth = .12+self.survey.spec["river_policy"]["depth_m_estimate"]*min(1.,edge/12)
        level = float(np.interp(s,self.stations,self.levels))
        foam = max(0.,1-p.distance(self.weir)/65)*max(0.,min(1.,(s-self.line.project(self.weir))/10))
        return [x,level,z,s,cross,depth,min(1.,edge/14),foam]

    def create(self):
        chunks = []
        for basin, polygon in [(-1,self.survey.river), *enumerate(self.survey.basins),(-2,self.ground_coverage.difference(self.coverage))]:
            minx,minz,maxx,maxz = polygon.bounds
            for x in range(math.floor(minx/1000)*1000,math.ceil(maxx/1000)*1000,1000):
                for z in range(math.floor(minz/1000)*1000,math.ceil(maxz/1000)*1000,1000):
                    clipped = polygon.intersection(box(x,z,x+1000,z+1000))
                    if clipped.area < 2:
                        continue
                    vertices=[]
                    step = self.survey.spec["river_policy"]["mesh_cell_m"]
                    cx0,cz0,cx1,cz1=clipped.bounds
                    for gx in range(math.floor(cx0/step)*step,math.ceil(cx1/step)*step,step):
                        for gz in range(math.floor(cz0/step)*step,math.ceil(cz1/step)*step,step):
                            tile=clipped.intersection(box(gx,gz,gx+step,gz+step))
                            if tile.area < .05: continue
                            for tri in constrained_delaunay_triangles(tile).geoms:
                                # 구멍과 오목한 경계를 가로지르는 삼각형을 제외한다.
                                if not tile.covers(tri): continue
                                points=list(tri.exterior.coords)[:3]
                                points.reverse()  # Godot의 시계 방향 표면.
                                vertices.extend([self.shore_vertex(round(px,5),round(pz,5)) if basin==-2 else self.vertex(round(px,5),round(pz,5),basin) for px,pz in points])
                    if vertices:
                        identifier=f"{'shore' if basin==-2 else 'river' if basin<0 else 'basin'+str(basin)}_{x}_{z}"
                        path=STAGE/(identifier+'.json')
                        path.write_text(json.dumps({'id':identifier,'origin':[x+500,0,z+500],'vertices':vertices,'still':basin>=0,'bed_only':basin==-2},separators=(',',':')),encoding='utf-8')
                        chunks.append({'id':identifier,'triangles':len(vertices)//3,'bed_only':basin==-2,'origin':[x+500,0,z+500],
                                       'scene_path':f'res://assets/generated/taehwa_civil/{identifier}.tscn'})
        self.rasters()
        return chunks

    def rasters(self):
        # 원본 지도 래스터 격자에 맞춘 작은 패치. 원본 파일은 쓰지 않는다.
        n=self.survey.dem.shape[0]; scale=(n-1)/self.survey.world_size
        xmin,zmin,xmax,zmax=self.ground_coverage.bounds
        px0=max(0,math.floor((xmin/80000+.5)*(n-1))-2)
        py0=max(0,math.floor((zmin/80000+.5)*(n-1))-2)
        px1=min(n,math.ceil((xmax/80000+.5)*(n-1))+3)
        py1=min(n,math.ceil((zmax/80000+.5)*(n-1))+3)
        width,height=px1-px0,py1-py0
        mask=Image.new('L',(width,height)); draw=ImageDraw.Draw(mask)
        def coordinates(ring): return [((x/80000+.5)*(n-1)-px0,(z/80000+.5)*(n-1)-py0) for x,z in ring.coords]
        polygons=list(self.ground_coverage.geoms) if hasattr(self.ground_coverage,'geoms') else [self.ground_coverage]
        for p in polygons:
            draw.polygon(coordinates(p.exterior),fill=255)
            for ring in p.interiors: draw.polygon(coordinates(ring),fill=0)
        values=np.zeros((height,width),dtype='<f4')
        for py,px in zip(*np.where(np.asarray(mask)>0)):
            x=((px+px0)/(n-1)-.5)*80000; z=((py+py0)/(n-1)-.5)*80000
            p=Point(x,z)
            if not self.ground_coverage.covers(p):
                mask.putpixel((int(px),int(py)),0)
                continue
            basin=next((i for i,g in enumerate(self.survey.basins) if g.covers(p)),-1)
            v=self.vertex(round(x,5),round(z,5),basin) if self.coverage.covers(p) else self.shore_vertex(round(x,5),round(z,5))
            values[py,px]=(v[1]-v[5]-self.survey.low)/(self.survey.high-self.survey.low)
        packed=struct.pack('<II',width,height)+zlib.compress(values.tobytes(),9)
        (OUT/'bed_patch.rf32z').write_bytes(packed)
        rgba=Image.new('RGBA',mask.size,(255,255,255,0)); rgba.putalpha(mask); rgba.save(OUT/'bed_mask.png')
        # 지형 제거 영역은 실제 메시보다 보수적으로 좁힌다. 래스터 경계 바깥 구멍을 막는다.
        fine=Image.new('L',(width*2,height*2)); pen=ImageDraw.Draw(fine)
        for polygon in polygons:
            pen.polygon([(x*2,y*2) for x,y in coordinates(polygon.exterior)],fill=255)
            for ring in polygon.interiors:pen.polygon([(x*2,y*2) for x,y in coordinates(ring)],fill=0)
        fine.filter(ImageFilter.MinFilter(3)).save(OUT/'overlay_mask.png')
        data={'source_path':self.survey.source.relative_to(self.survey.source.parents[3]).as_posix(),
              'source_sha256':self.survey.source_hash,'source_resolution':[n,n],
              'pixel_rect':[px0,py0,width,height],'height_min':self.survey.low,'height_max':self.survey.high,
              'world_rect':[ (px0/(n-1)-.5)*80000,(py0/(n-1)-.5)*80000,width/(n-1)*80000,height/(n-1)*80000],
              'water_bbox':list(self.coverage.bounds),'affected_pixels':int(np.count_nonzero(np.asarray(mask))),
              'elevation_min_m':float(values[np.asarray(mask)>0].min()*(self.survey.high-self.survey.low)+self.survey.low),
              'elevation_max_m':float(values[np.asarray(mask)>0].max()*(self.survey.high-self.survey.low)+self.survey.low),
              'depth_status':'visual_estimate','source_modified':False}
        (OUT/'bed_patch.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
        (OUT/'hydro_boundary.geojson').write_text(json.dumps({'type':'FeatureCollection','features':[{'type':'Feature','properties':{'id':'taehwa_overlay','status':'mapped_lower_and_estimated_upper_width','source':'OpenStreetMap contributors / ODbL-1.0'},'geometry':mapping(transform(self.survey.lonlat,self.coverage))}]},separators=(',',':')),encoding='utf-8')
