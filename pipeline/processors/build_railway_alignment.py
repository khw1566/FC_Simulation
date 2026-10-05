"""철도 종단을 연속화하고 절성토 높이맵 및 터널 배치를 함께 생성한다."""
import hashlib
import heapq
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image


class RailwayAlignmentBuilder:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        root = self.ROOT
        settings = json.loads((root/"config/railway_alignment.json").read_text(encoding="utf-8"))
        meta = json.loads((root/"godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8-sig"))
        network = json.loads((root/"godot_project/assets/generated/railway/network.json").read_text(encoding="utf-8"))
        source = root/"godot_project"/meta["assets"]["heightmap"].removeprefix("res://")
        with Image.open(source) as image:
            raw = np.asarray(image).astype(np.float32)
        raw = meta["min_elevation"]+raw/65535.0*(meta["max_elevation"]-meta["min_elevation"])
        bbox, size = meta["bbox"], meta["world_size_meters"]
        def project(p):
            return np.array([(p[0]-bbox["west"])/(bbox["east"]-bbox["west"])*size-size/2,(bbox["north"]-p[1])/(bbox["north"]-bbox["south"])*size-size/2])
        def sample(p):
            x=np.clip((p[0]/size+0.5)*(raw.shape[1]-1),0,raw.shape[1]-1)
            y=np.clip((p[1]/size+0.5)*(raw.shape[0]-1),0,raw.shape[0]-1)
            ix,iy=int(x),int(y)
            ix1,iy1=min(ix+1,raw.shape[1]-1),min(iy+1,raw.shape[0]-1)
            return float((raw[iy,ix]*(1-(x-ix))+raw[iy,ix1]*(x-ix))*(1-(y-iy))+(raw[iy1,ix]*(1-(x-ix))+raw[iy1,ix1]*(x-ix))*(y-iy))
        positions, targets, lookup, edges, tracks = [], [], {}, [], []
        for track in network["tracks"]:
            original = [project(p) for p in track["points"]]
            dense, originals = [original[0]], [0]
            for a,b in zip(original,original[1:]):
                count=max(1,math.ceil(float(np.linalg.norm(b-a))/settings["sample_step_m"]))
                dense.extend(a+(b-a)*i/count for i in range(1,count+1))
                originals.append(len(dense)-1)
            distances=np.r_[0,np.cumsum([np.linalg.norm(b-a) for a,b in zip(dense,dense[1:])])]
            endpoint=[sample(original[0]),sample(original[-1])]
            ids=[]
            for index,p in enumerate(dense):
                key=(round(float(p[0]),3),round(float(p[1]),3))
                height=sample(p)+settings["formation_offset_m"]
                if track["bridge"] or track["tunnel"]:
                    fraction=distances[index]/max(distances[-1],0.01)
                    height=endpoint[0]*(1-fraction)+endpoint[1]*fraction+settings["formation_offset_m"]
                    if track["bridge"]:
                        height+=6*math.sin(math.pi*fraction)**2
                if key not in lookup:
                    lookup[key]=len(positions)
                    positions.append(p)
                    targets.append(height)
                ids.append(lookup[key])
                if index>0 and ids[-1]!=ids[-2]:
                    edges.append((ids[-2],ids[-1],float(np.linalg.norm(dense[index]-dense[index-1]))))
            tracks.append({"osm_id":track["osm_id"],"service":track["service"],"bridge":track["bridge"],"tunnel":track["tunnel"],"ids":ids,"original_indices":originals,"coordinates":track["points"]})
        positions=np.asarray(positions)
        heights=np.asarray(targets)
        a=np.array([e[0] for e in edges]); b=np.array([e[1] for e in edges]); spans=np.array([e[2] for e in edges])
        degree=np.bincount(np.r_[a,b],minlength=len(heights))
        for _ in range(settings["smoothing_passes"]):
            total=np.bincount(a,weights=heights[b],minlength=len(heights))+np.bincount(b,weights=heights[a],minlength=len(heights))
            heights=0.5*heights+0.5*total/np.maximum(degree,1)
        draft=[]
        for track in tracks:
            item=track.copy()
            item["points"]=[[round(float(positions[i][0]),3),float(heights[i]),round(float(positions[i][1]),3)] for i in track["ids"]]
            draft.append(item)
        # 여러 OSM way로 나뉜 터널도 전체 갱구 사이 종단을 사용한다.
        for chain in self.tunnel_chains(draft):
            ps=chain["points"]
            ds=np.r_[0,np.cumsum([math.hypot(b[0]-a[0],b[2]-a[2]) for a,b in zip(ps,ps[1:])])]
            for p,d in zip(ps,ds):
                heights[lookup[(p[0],p[2])]]=ps[0][1]+(ps[-1][1]-ps[0][1])*d/max(ds[-1],0.001)
        # 양방향 최단 경로 포락선은 모든 공유 절점에서 경사 한계를 만족한다.
        adjacency=[[] for _ in heights]
        for left,right,distance in edges:
            adjacency[left].append((right,distance*settings["maximum_grade"]))
            adjacency[right].append((left,distance*settings["maximum_grade"]))
        heights=(self.envelope(heights,adjacency)-self.envelope(-heights,adjacency))*0.5
        for track in tracks:
            track["points"]=[[round(float(positions[i][0]),3),round(float(heights[i]),4),round(float(positions[i][1]),3)] for i in track.pop("ids")]
        tunnels=self.pair_tunnels(self.tunnel_chains(tracks))
        graded=raw.copy()
        weight=np.zeros(raw.shape,dtype=np.float32)
        desired=np.zeros(raw.shape,dtype=np.float32)
        for track in tracks:
            if track["bridge"] or track["tunnel"]:
                continue
            for p in track["points"]:
                self.paint(graded,desired,weight,p,size,settings["formation_half_width_m"],settings["earthwork_blend_width_m"],p[1]-settings["formation_offset_m"])
        active=weight>0
        graded[active]=graded[active]*(1-weight[active])+desired[active]*weight[active]
        # 입출구는 개방 절개로 연결하고 내부는 천장 위의 지표를 유지한다.
        for tunnel in tunnels:
            points=tunnel["points"]
            distance=0.0
            total=sum(math.dist(a,b) for a,b in zip(points,points[1:]))
            for i,p in enumerate(points):
                if i:
                    distance+=math.dist(points[i-1],p)
                mouth=min(distance,total-distance)
                half=8.5 if tunnel["service"]=="ktx" else 7.0
                if mouth<35:
                    self.cut_portal(graded,p,size,half,mouth)
        void=np.zeros((*raw.shape,4),dtype=np.uint8)
        for track in tracks:
            if not track["bridge"] and not track["tunnel"]:
                for point in track["points"]:
                    self.paint_void(void,point,size,meta,5.5,0)
        for tunnel in tunnels:
            for point in tunnel["points"]:
                self.paint_void(void,point,size,meta,8.5 if tunnel["service"]=="ktx" else 7.0,11 if tunnel["service"]=="ktx" else 10)
        destination=root/"godot_project/assets/generated/railway/alignment.json"
        payload={"version":1,"map_id":"ulsan_metro_80km","settings":settings,"tracks":tracks,"tunnels":tunnels}
        destination.write_text(json.dumps(payload,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
        height_path=destination.with_name("graded_heightmap_16bit.png")
        normalized=np.clip((graded-meta["min_elevation"])/(meta["max_elevation"]-meta["min_elevation"])*65535,0,65535).astype(np.uint16)
        Image.fromarray(normalized).save(height_path)
        void_path=destination.with_name("tunnel_void.png")
        Image.fromarray(void).save(void_path)
        manifest_path=root/"godot_project/assets/generated/manifest.json"
        manifest=json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        for key,path,kind,resolution in [("railway_alignment",destination,"railway_alignment_catalog",settings["sample_step_m"]),("railway_graded_heightmap",height_path,"heightmap_16bit",[raw.shape[1],raw.shape[0]]),("railway_tunnel_void",void_path,"tunnel_void_mask",[raw.shape[1],raw.shape[0]])]:
            manifest.setdefault("assets",{})[key]={"file_path":"res://"+path.relative_to(root/"godot_project").as_posix(),"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"bbox":bbox,"elevation_min":float(graded.min()),"elevation_max":float(graded.max()),"resolution":resolution,"type":kind,"source_path":meta["assets"]["heightmap"],"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest()}
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        grade=np.abs(heights[b]-heights[a])/np.maximum(spans,0.001)
        report={"tracks":len(tracks),"tunnel_groups":len(tunnels),"maximum_grade":float(grade.max()),"target_maximum_grade":settings["maximum_grade"],"shared_nodes":len(positions),"note":"생성 시 종단 경사 통계. 전체 맵 실행과 렌더 검증은 생략."}
        (root/"results/261004_RailwayAlignmentGeneration.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
        print("ALIGNMENT",len(tracks),"TUNNELS",len(tunnels),"MAX_GRADE",float(grade.max()))

    def envelope(self, values, adjacency):
        result=values.copy()
        queue=[(float(value),i) for i,value in enumerate(result)]
        heapq.heapify(queue)
        while queue:
            value,i=heapq.heappop(queue)
            if value>result[i]+1e-9:
                continue
            for j,cost in adjacency[i]:
                if value+cost<result[j]-1e-9:
                    result[j]=value+cost
                    heapq.heappush(queue,(value+cost,j))
        return result

    def pair_tunnels(self, chains):
        result=[]
        used=set()
        def length(points):
            return sum(math.dist(a,b) for a,b in zip(points,points[1:]))
        for i,chain in enumerate(chains):
            if i in used:
                continue
            ps=np.array(chain["points"])
            for j,other in enumerate(chains):
                if j<=i or j in used or other["service"]!=chain["service"]:
                    continue
                qs=np.array(other["points"])
                if np.linalg.norm(ps[0]-qs[-1])<np.linalg.norm(ps[0]-qs[0]):
                    qs=qs[::-1]
                if max(np.linalg.norm(ps[0]-qs[0]),np.linalg.norm(ps[-1]-qs[-1]))>18 or abs(length(ps)-length(qs))>100:
                    continue
                distances=np.r_[0,np.cumsum(np.linalg.norm(np.diff(qs,axis=0),axis=1))]
                own=np.r_[0,np.cumsum(np.linalg.norm(np.diff(ps,axis=0),axis=1))]
                matching=np.column_stack([np.interp(own/own[-1]*distances[-1],distances,qs[:,k]) for k in range(3)])
                chain["points"]=np.round((ps+matching)*0.5,4).tolist()
                chain["members"]+=other["members"]
                spacing=float(np.linalg.norm((ps[0]-matching[0])[[0,2]]))
                chain["width_scale"]=max(0.85,min(1.5,spacing/(5.4 if chain["service"]=="ktx" else 4.4)))
                used.add(j)
                break
            result.append(chain)
        return result

    def tunnel_chains(self, tracks):
        selected={t["osm_id"]:t for t in tracks if t["tunnel"]}
        endpoints={}
        for id,t in selected.items():
            for p in (t["points"][0],t["points"][-1]):
                endpoints.setdefault((t["service"],p[0],p[2]),[]).append(id)
        remaining=set(selected)
        chains=[]
        while remaining:
            id=min(remaining)
            t=selected[id]
            points=list(t["points"]); members=[id]; remaining.remove(id)
            for reverse in (False,True):
                if reverse:
                    points.reverse()
                while True:
                    p=points[-1]
                    candidates=[i for i in endpoints[(t["service"],p[0],p[2])] if i in remaining]
                    if len(candidates)!=1:
                        break
                    other=selected[candidates[0]]
                    addition=list(other["points"])
                    if addition[0][0]!=p[0] or addition[0][2]!=p[2]:
                        addition.reverse()
                    points.extend(addition[1:]);members.append(other["osm_id"]);remaining.remove(other["osm_id"])
            chains.append({"id":"tunnel_"+str(min(members)),"service":t["service"],"members":members,"points":points,"width_scale":0.6})
        return chains

    def paint(self, graded, desired, weight, point, size, half, blend, value):
        x=(point[0]/size+0.5)*(graded.shape[1]-1)
        y=(point[2]/size+0.5)*(graded.shape[0]-1)
        cell=size/(graded.shape[1]-1)
        radius=math.ceil((half+blend)/cell)
        x0,x1=max(0,int(x)-radius),min(graded.shape[1],int(x)+radius+2)
        y0,y1=max(0,int(y)-radius),min(graded.shape[0],int(y)+radius+2)
        if x0>=x1 or y0>=y1:
            return
        yy,xx=np.mgrid[y0:y1,x0:x1]
        distance=np.hypot(xx-x,yy-y)*cell
        w=np.clip(1-(distance-half)/blend,0,1)
        w=w*w*(3-2*w)
        replace=w>weight[y0:y1,x0:x1]
        desired[y0:y1,x0:x1][replace]=value
        weight[y0:y1,x0:x1][replace]=w[replace]

    def cut_portal(self, graded, point, size, half, distance):
        x=(point[0]/size+0.5)*(graded.shape[1]-1)
        y=(point[2]/size+0.5)*(graded.shape[0]-1)
        cell=size/(graded.shape[1]-1)
        half=max(half,cell*0.8)
        radius=max(1,math.ceil(half/cell))
        x0,x1=max(0,int(x)-radius),min(graded.shape[1],int(x)+radius+2)
        y0,y1=max(0,int(y)-radius),min(graded.shape[0],int(y)+radius+2)
        if x0>=x1 or y0>=y1:
            return
        yy,xx=np.mgrid[y0:y1,x0:x1]
        mask=np.hypot(xx-x,yy-y)*cell<half
        patch=graded[y0:y1,x0:x1]
        # 갱구 바닥과 바깥 절개는 지표가 통로를 막지 않도록 낮춘다.
        patch[mask]=point[1]-0.55

    def paint_void(self, mask, point, size, meta, half, height):
        x=(point[0]/size+0.5)*(mask.shape[1]-1)
        y=(point[2]/size+0.5)*(mask.shape[0]-1)
        cell=size/(mask.shape[1]-1)
        half=max(half,cell*0.8)
        radius=max(1,math.ceil(half/cell))
        x0,x1=max(0,int(x)-radius),min(mask.shape[1],int(x)+radius+2)
        y0,y1=max(0,int(y)-radius),min(mask.shape[0],int(y)+radius+2)
        if x0>=x1 or y0>=y1:
            return
        yy,xx=np.mgrid[y0:y1,x0:x1]
        selected=np.hypot(xx-x,yy-y)*cell<half
        encoded=int(np.clip((point[1]-1.5-meta["min_elevation"])/(meta["max_elevation"]-meta["min_elevation"])*65535,0,65535))
        if height==0:
            encoded=int(np.clip((point[1]-0.25-meta["min_elevation"])/(meta["max_elevation"]-meta["min_elevation"])*65535,0,65535))
        mask[y0:y1,x0:x1][selected]=[encoded//256,encoded%256,255 if height else 128,height]


if __name__=="__main__":
    RailwayAlignmentBuilder().run()
