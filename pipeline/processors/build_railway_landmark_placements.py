"""기존 OSM 철도와 역사 윤곽에 맞춘 에셋 배치 목록 생성."""
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET


class RailwayLandmarkPlacementBuilder:
    ROOT = Path(__file__).resolve().parents[2]

    def run(self):
        root = self.ROOT
        network = json.loads((root / "godot_project/assets/generated/railway/network.json").read_text(encoding="utf-8"))
        xml = ET.parse(root / "data/raw/ulsan_metro_80km/railway/taehwa_station.osm").getroot()
        nodes = {n.get("id"):[float(n.get("lon")),float(n.get("lat"))] for n in xml.findall("node")}
        way = next(w for w in xml.findall("way") if w.get("id")=="999444305")
        footprint = [nodes[n.get("ref")] for n in way.findall("nd")][:-1]
        center = [sum(p[i] for p in footprint)/len(footprint) for i in (0,1)]
	
        meta = json.loads((root / "godot_project/assets/maps/ulsan_metro_80km/map_meta.json").read_text(encoding="utf-8-sig"))
        bbox = meta["bbox"]
        offsets = [((p[0]-center[0])/(bbox["east"]-bbox["west"]),(center[1]-p[1])/(bbox["north"]-bbox["south"])) for p in footprint]
        xx=sum(x*x for x,z in offsets)
        zz=sum(z*z for x,z in offsets)
        xz=sum(x*z for x,z in offsets)
        yaw=-0.5*math.atan2(2*xz,xx-zz)
        if math.sin(yaw)>0:
            yaw+=math.pi
        bridges = []
        for track in network["tracks"]:
            near_taehwa = track["service"]=="donghae" and any(129.35<p[0]<129.364 and 35.541<p[1]<35.5562 for p in track["points"])
            if track["bridge"] and (near_taehwa or track["osm_id"] in (128255609,407197573)):
                bridges.append({"osm_id":track["osm_id"],"kind":"anyang" if track["osm_id"] in (128255609,407197573) else "generic","points":track["points"]})
        stops = []
        for route in network["routes"]:
            for stop in route["stops"]:
                if stop["name"]=="울산":
                    index=stop["point_index"]
                    stops.append({"id":"ulsan_station_interface","points":route["points"][index-1:index+2]})
        data = {"version":1,"maps":["ulsan_metro_80km"],"station":{"id":"taehwagang","coordinate":center,"yaw_degrees":math.degrees(yaw),"glb_path":"res://assets/generated/taehwagang/station.glb","footprint":footprint,"excluded_osm_id":999444305},"bridges":bridges,"interfaces":stops,"note":"태화강역 역사만 배치. 제작용 역 구내 선로·주변 구역은 OSM과 중복되어 제외. 안양교는 본체와 접근부를 실제 철도 선형에 맞춰 변형하며 울산역 전체 건물은 포함하지 않음."}
        destination = root / "godot_project/assets/generated/railway/landmark_placements.json"
        destination.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
        manifest_path=root / "godot_project/assets/generated/manifest.json"
        manifest=json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        all_points=footprint+[p for bridge in bridges for p in bridge["points"]]
        manifest.setdefault("assets",{})["railway_landmark_placements"]={"file_path":"res://assets/generated/railway/landmark_placements.json","sha256":hashlib.sha256(destination.read_bytes()).hexdigest(),"bbox":{"west":min(p[0] for p in all_points),"east":max(p[0] for p in all_points),"south":min(p[1] for p in all_points),"north":max(p[1] for p in all_points)},"elevation_min":meta["min_elevation"]-1,"elevation_max":meta["max_elevation"]+27,"elevation_bounds_mode":"지도 고도 범위와 모델 높이를 포함하는 보수적 경계; 실제 배치 고도는 실행 시 지형에서 결정","resolution":"현재 지도 지형과 OSM 철도 선형에 실행 시 정합","type":"railway_landmark_placement","note":data["note"]}
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
        print("STATION=1 BRIDGE_TRACKS=",len(bridges))


if __name__=="__main__":
    RailwayLandmarkPlacementBuilder().run()
