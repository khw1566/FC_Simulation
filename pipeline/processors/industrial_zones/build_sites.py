"""항포구 주변 후보 선정부터 공단 도로·필지·설비 배치 데이터 생성."""
import hashlib
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import shape, box, mapping
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from industrial_zones.site_inputs import IndustrialSiteInputs
from industrial_zones.road_graph import IndustrialRoadGraph
from industrial_zones.parcel_builder import IndustrialParcelBuilder
from industrial_zones.asset_placer import IndustrialAssetPlacer
from industrial_zones.build_masks import IndustrialZoneMaskBuilder
from simple_maps.publish import atomic, merge


class IndustrialSiteBuilder:
    def run(self):
        config = IndustrialSiteInputs.read(ROOT/"config/industrial_zones.json")
        inputs = IndustrialSiteInputs(ROOT,config)
        folder = ROOT/f"godot_project/assets/generated/industrial_zones/{config['map_id']}"
        folder.mkdir(parents=True,exist_ok=True)
        catalog = IndustrialSiteInputs.read(ROOT/"godot_project/assets/generated/industrial/catalog.json")["assets"]
        plant_catalog = IndustrialSiteInputs.read(ROOT/"godot_project/assets/generated/industrial_plant/catalog.json")["assets"]
        # 공정 탑의 연결 포트 (-12,5,0)에 랙의 오른쪽 포트 (12,5,0)를 접속한다.
        for key in ("stack_steel","stack_concrete","process_column","scrubber_tower"):
            spec = dict(plant_catalog[key])
            spec["aabb_min_m"] = list(spec["aabb_min_m"])
            spec["aabb_min_m"][0] = -36.0
            lo,hi = spec["aabb_min_m"],spec["aabb_max_m"]
            spec["footprint_xz_m"] = [lo[0],lo[2],hi[0],hi[2]]
            spec["scale_range"] = [1.0,1.0]
            spec["attachments"] = [{"asset_type":"rack_straight","position_m":[-24,0,0],
                                    "glb_path":plant_catalog["rack_straight"]["scene_path"].replace(".tscn",".glb"),
                                    "night_lighting":plant_catalog["rack_straight"].get("night_lighting",{}),
                                    "port_parent_m":[-12,5,0],"port_attachment_m":[12,5,0]}]
            catalog[key] = spec
        regions_path = ROOT/config["regions_path"]
        source = IndustrialSiteInputs.read(regions_path)
        sites = []
        if not source["features"] and config.get("auto_candidates_enabled",False):
            reservation = inputs.raster.copy()
            for polygon in inputs.protected:
                inputs.rasterize(polygon,reservation)
            blocked = np.asarray(reservation)>0
            for zone_id,harbor in enumerate(inputs.anchors,1):
                center = inputs.project([harbor["lon"],harbor["lat"]])
                candidates = []
                extent = float(config.get("candidate_size_m",1200))
                for dz in range(-2800,2801,400):
                    for dx in range(-3200,1601,400):
                        x,z = center[0]+dx,center[1]+dz
                        region = box(x-extent/2,z-extent/2,x+extent/2,z+extent/2)
                        if any(region.intersects(s["geometry"].buffer(100)) for s in sites):
                            continue
                        x0=int((region.bounds[0]/inputs.size+0.5)*(inputs.resolution-1))
                        x1=int((region.bounds[2]/inputs.size+0.5)*(inputs.resolution-1))+1
                        y0=int((region.bounds[1]/inputs.size+0.5)*(inputs.resolution-1))
                        y1=int((region.bounds[3]/inputs.size+0.5)*(inputs.resolution-1))+1
                        free = 1-float(blocked[y0:y1,x0:x1].mean())
                        if free>0.3:
                            candidates.append((free-0.00001*(abs(dx)+abs(dz)),dx,dz,region))
                profile_name = "general_factory" if harbor["id"]=="ulsan_main" else "petrochemical"
                found = None
                for _,dx,dz,region in sorted(candidates,key=lambda c:c[0],reverse=True)[:45]:
                    site = self.generate(region,inputs,config,catalog,profile_name,zone_id)
                    if site and len(site["placements"])>=10:
                        found = site
                        break
                if found is None:
                    raise RuntimeError(harbor["name_ko"]+": 연결 도로와 10개 이상의 설비를 배치할 안전한 후보 없음")
                found.update(name_ko=harbor["name_ko"]+" 절차 공단",geometry=region,profile=profile_name,zone_id=zone_id)
                sites.append(found)
                print("SITE",found["name_ko"],"assets",len(found["placements"]),"roads",len(found["graph"]["roads"]),flush=True)
            features = []
            for site in sites:
                ring = [inputs.geographic(p) for p in site["geometry"].exterior.coords]
                features.append({"type":"Feature","properties":{"zone_id":site["zone_id"],"name_ko":site["name_ko"],
                                 "profile":site["profile"],"seed":config["seed"]+site["zone_id"],"status":"confirmed",
                                 "source":"local_safe_land_candidate","accuracy":"게임용 후보 구역, 실제 공단 경계 아님"},
                                 "geometry":{"type":"Polygon","coordinates":[ring]}})
            atomic(regions_path,{**source,"features":features})
        else:
            from shapely.ops import transform
            for feature in source["features"]:
                props = feature["properties"]
                if props.get("status")!="confirmed":
                    continue
                geometry = transform(lambda lon,lat,z=None: inputs.project([lon,lat]),shape(feature["geometry"]))
                if not geometry.is_valid:
                    raise ValueError("공단 경계가 자기 교차하거나 유효하지 않습니다")
                site = self.generate(geometry,inputs,config,catalog,props["profile"],props["zone_id"],props.get("seed"))
                if site is None:
                    raise RuntimeError(props["name_ko"]+": 기존 도로와 연결 가능한 도로망이 없습니다")
                site.update(name_ko=props["name_ko"],geometry=geometry,profile=props["profile"],zone_id=props["zone_id"])
                sites.append(site)
        if not sites:
            raise RuntimeError("생성할 확정 구역이 없습니다")
        # 기본 마스크를 갱신한 다음 전체 기존 시설·경사 제외 결과로 허용 마스크를 보강한다.
        IndustrialZoneMaskBuilder().run()
        allowed = Image.new("L",(inputs.resolution,inputs.resolution))
        zones,roads,placements,parcels = [],[],[],[]
        for site in sites:
            inputs.rasterize(site["asset_safe"],allowed)
            center = site["geometry"].centroid
            zones.append({"zone_id":site["zone_id"],"name_ko":site["name_ko"],"profile":site["profile"],
                          "world_polygon":mapping(site["geometry"]),"center_xz":[center.x,center.y],"connection":site["graph"]["connection"],
                          "connected_nodes":site["graph"]["connected_nodes"],"component_count":1,
                          "preserve_existing_buildings":True,"asset_count":len(site["placements"]),"road_count":len(site["graph"]["roads"])})
            for road in site["graph"]["roads"]:
                roads.append({**road,"id":f"zone_{site['zone_id']}_"+road["id"],"zone_id":site["zone_id"]})
            placements.extend(site["placements"])
            for index,polygon in enumerate(site["parcels"]):
                parcels.append({"zone_id":site["zone_id"],"parcel_id":index,"geometry":mapping(polygon),"area_m2":polygon.area})
        allowed.save(folder/"allowed.png")
        excluded = Image.fromarray(255-np.asarray(allowed))
        excluded.save(folder/"excluded_all.png")
        atomic(folder/"roads.json",{"version":1,"map_id":config["map_id"],"roads":roads,"zones":zones})
        atomic(folder/"parcels.json",{"version":1,"parcels":parcels})
        atomic(folder/"placements.json",{"version":1,"map_id":config["map_id"],"settings":{
               "enabled":True,"detail_distance_m":2600,"render_distance_m":9000,"chunk_size_m":600,"creation_budget_per_frame":2},
               "zones":zones,"placements":placements,"roads_path":"res://"+(folder/"roads.json").relative_to(ROOT/"godot_project").as_posix(),
               "regions_source_sha256":hashlib.sha256(regions_path.read_bytes()).hexdigest(),
               "source_policy":"게임용 후보와 고정 seed. 기존 건물·도로·철도·수계·공항·문화유산 보존."})
        region_catalog = IndustrialSiteInputs.read(folder/"regions.json")
        region_catalog.update(road_generation_enabled=True,allowed_pixels=int((np.asarray(allowed)>0).sum()),
                              note_ko="확정 구역에서 수계·급경사·기존 건물·도로·철도·공항·문화유산을 제외한 배치 허용 영역")
        atomic(folder/"regions.json",region_catalog)
        self.preview(folder,sites)
        self.write_description(folder)
        entries = {}
        for path in folder.iterdir():
            if path.name=="manifest.json":
                continue
            resolution = {"type":"procedural_layout"}
            if path.suffix==".png":
                with Image.open(path) as image:
                    resolution = {"width":image.width,"height":image.height}
            entries[f"industrial_zones/{config['map_id']}/{path.name}"] = {
                "file_path":"res://"+path.relative_to(ROOT/"godot_project").as_posix(),"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                "bbox":inputs.bbox,"elevation_min":min(p["foundation_bottom_y"] for p in placements),
                "elevation_max":max(p["position"][1]+p["aabb_max_m"][1]*p["scale"] for p in placements),"resolution":resolution,"type":"industrial_zone_layout"}
        atomic(folder/"manifest.json",{"version":2,"assets":entries})
        merge(ROOT/"godot_project/assets/generated/manifest.json",entries)
        report={"zones":len(zones),"roads":len(roads),"assets":len(placements),"parcels":len(parcels),"failures":[],
                "method":"연속 도로 연결 그래프, 전체 footprint·진입 공간·기존 시설·수계·경사·기초 고저 차 검사"}
        atomic(ROOT/"results/261004_IndustrialSitesGeneration.json",report)
        print(json.dumps(report,ensure_ascii=False),flush=True)

    def generate(self,geometry,inputs,config,catalog,profile_name,zone_id,seed=None):
        seed = int(config["seed"]+zone_id if seed is None else seed)
        rng = random.Random(seed)
        profile = config["profiles"][profile_name]
        road_safe = inputs.safe_geometry(geometry)
        asset_safe = inputs.safe_geometry(geometry,include_roads=True)
        graph = IndustrialRoadGraph().build(geometry,road_safe,inputs,profile,rng)
        if graph is None:
            return None
        parcels = IndustrialParcelBuilder().build(asset_safe,graph)
        placements = IndustrialAssetPlacer().build(parcels,graph,inputs,profile_name,profile,catalog,rng,zone_id,road_safe)
        return {"graph":graph,"parcels":parcels,"placements":placements,"asset_safe":asset_safe}

    @staticmethod
    def write_description(folder):
        text = """# 울산 절차 공단 배치 데이터
울산 본항·온산항 주변의 게임용 육지 후보를 사용한다. 실제 공단 경계나 실제 시설 배치를 재현한 자료가 아니다.

- `zone_ids.png`: 16bit 구역 ID. 0은 구역 밖이다.
- `excluded_water.png`: 수계와 해안 이격 제외 마스크.
- `allowed.png`: 확정 구역에서 수계·경사·기존 시설·도로를 제외한 설비 후보 영역.
- `excluded_all.png`: 허용 마스크의 반전. 도로 생성은 별도의 도로 안전 영역을 사용한다.
- `regions.json`: 구역 상태와 경계 원본 해시.
- `roads.json`: 내부 도로 중심선·폭과 기존 도로 접속점.
- `parcels.json`: 필지 경계.
- `placements.json`: 설비·기초·진입로·부착 배관·조명 참조와 표시 거리 설정.
- `layout_preview.png`: 흑백 배치도. 기존 건물과 기존 도로의 상세 모델은 표시하지 않는다.
- `manifest.json`: 산출물 SHA256·지도 bbox·배치 고도 범위·해상도.

경계는 `config/industrial_zones.geojson`, 규칙은 `config/industrial_zones.json`에서 관리한다. 기존 경계가 있으면 해당 경계를 사용한다. 자동 후보 지정은 경계 목록이 비어 있고 자동 지정 설정이 켜져 있을 때만 수행한다.

프로젝트 루트에서 명시적 가상환경으로 배치와 색인을 차례로 갱신한다.

```powershell
& '.\\.venv_campus\\Scripts\\python.exe' pipeline/processors/industrial_zones/build_sites.py
& '.\\.venv_campus\\Scripts\\python.exe' pipeline/indexer/build_asset_index.py
```

마스크 생성기만 실행하면 기존 시설을 고려한 배치 결과까지 갱신되지 않는다. 배치 변경에는 `build_sites.py`를 사용한다. 게임에서는 울산 80km 맵의 설정에서 `절차 생성 공단 표시`를 켜거나 끌 수 있다.
"""
        (folder/"README.md").write_text(text,encoding="utf-8")

    @staticmethod
    def preview(folder,sites):
        image = Image.new("RGB",(900*len(sites),940),(25,25,25))
        draw = ImageDraw.Draw(image)
        for index,site in enumerate(sites):
            bounds=site["geometry"].bounds
            size=max(bounds[2]-bounds[0],bounds[3]-bounds[1])
            def pixel(p):
                return (index*900+30+(p[0]-bounds[0])/size*840,60+(p[1]-bounds[1])/size*840)
            draw.text((index*900+30,20),f"Zone {site['zone_id']} / {site['profile']} / {len(site['placements'])} assets",fill="white")
            polygons=[site["asset_safe"]] if site["asset_safe"].geom_type=="Polygon" else getattr(site["asset_safe"],"geoms",[])
            for polygon in polygons:
                if polygon.geom_type!="Polygon":
                    continue
                draw.polygon([pixel(p) for p in polygon.exterior.coords],fill=(110,110,110))
                for ring in polygon.interiors:
                    draw.polygon([pixel(p) for p in ring.coords],fill=(25,25,25))
            for road in site["graph"]["roads"]:
                draw.line([pixel(p) for p in road["points_xz"]],fill="white",width=max(2,int(road["width_m"]/size*840)))
            for placement in site["placements"]:
                draw.polygon([pixel(p) for p in placement["footprint_xz"]],fill=(45,45,45),outline=(220,220,220))
        image.save(folder/"layout_preview.png")


if __name__=="__main__":
    IndustrialSiteBuilder().run()
